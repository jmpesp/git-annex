{- git-annex command
 -
 - Copyright 2010-2021 Joey Hess <id@joeyh.name>
 -
 - Licensed under the GNU AGPL version 3 or higher.
 -}

{-# LANGUAGE OverloadedStrings #-}

module Command.Drop where

import Command
import qualified Remote
import qualified Annex
import Annex.UUID
import Logs.Location
import Logs.Trust
import Logs.PreferredContent
import Annex.NumCopies
import Annex.Content
import Annex.Wanted
import Annex.Notification

cmd :: Command
cmd = withGlobalOptions [jobsOption, jsonOptions, annexedMatchingOptions] $
	command "drop" SectionCommon
		"remove content of files from repository"
		paramPaths (seek <$$> optParser)

data DropOptions = DropOptions
	{ dropFiles :: CmdParams
	, dropFrom :: Maybe (DeferredParse Remote)
	, autoMode :: Bool
	, keyOptions :: Maybe KeyOptions
	, batchOption :: BatchMode
	}

optParser :: CmdParamsDesc -> Parser DropOptions
optParser desc = DropOptions
	<$> cmdParams desc
	<*> optional parseDropFromOption
	<*> parseAutoOption
	<*> optional parseKeyOptions
	<*> parseBatchOption

parseDropFromOption :: Parser (DeferredParse Remote)
parseDropFromOption = parseRemoteOption <$> strOption
	( long "from" <> short 'f' <> metavar paramRemote
	<> help "drop content from a remote"
	<> completeRemotes
	)

seek :: DropOptions -> CommandSeek
seek o = startConcurrency commandStages $ do
	from <- case dropFrom o of
		Nothing -> pure Nothing
		Just f -> getParsed f >>= \remote -> do
			u <- getUUID
			if Remote.uuid remote == u
				then pure Nothing
				else pure (Just remote)				
	let seeker = AnnexedFileSeeker
		{ startAction = start o from
		, checkContentPresent = case from of
			Nothing -> Just True
			Just _ -> Nothing
		, usesLocationLog = True
		}
	case batchOption o of
		Batch fmt -> batchAnnexedFilesMatching fmt seeker
		NoBatch -> withKeyOptions (keyOptions o) (autoMode o) seeker
			(commandAction . startKeys o from)
			(withFilesInGitAnnex ww seeker)
			=<< workTreeItems ww (dropFiles o)
  where
	ww = WarnUnmatchLsFiles

start :: DropOptions -> Maybe Remote -> SeekInput -> RawFilePath -> Key -> CommandStart
start o from si file key = start' o from key afile ai si
  where
	afile = AssociatedFile (Just file)
	ai = mkActionItem (key, afile)

start' :: DropOptions -> Maybe Remote -> Key -> AssociatedFile -> ActionItem -> SeekInput -> CommandStart
start' o from key afile ai si = 
	checkDropAuto (autoMode o) from afile key $ \numcopies mincopies ->
		stopUnless wantdrop $
			case from of
				Nothing -> startLocal pcc afile ai si numcopies mincopies key [] ud
				Just remote -> startRemote pcc afile ai si numcopies mincopies key ud remote
  where
	wantdrop
		| autoMode o = wantDrop False (Remote.uuid <$> from) (Just key) afile Nothing
		| otherwise = return True
	pcc = PreferredContentChecked (autoMode o)
	ud = case (batchOption o, keyOptions o) of
		(NoBatch, Just WantUnusedKeys) -> DroppingUnused True
		_ -> DroppingUnused False

startKeys :: DropOptions -> Maybe Remote -> (SeekInput, Key, ActionItem) -> CommandStart
startKeys o from (si, key, ai) = start' o from key (AssociatedFile Nothing) ai si

startLocal :: PreferredContentChecked -> AssociatedFile -> ActionItem -> SeekInput -> NumCopies -> MinCopies -> Key -> [VerifiedCopy] -> DroppingUnused -> CommandStart
startLocal pcc afile ai si numcopies mincopies key preverified ud =
	starting "drop" (OnlyActionOn key ai) si $
		performLocal pcc key afile numcopies mincopies preverified ud

startRemote :: PreferredContentChecked -> AssociatedFile -> ActionItem -> SeekInput -> NumCopies -> MinCopies -> Key -> DroppingUnused -> Remote -> CommandStart
startRemote pcc afile ai si numcopies mincopies key ud remote = 
	starting ("drop " ++ Remote.name remote) (OnlyActionOn key ai) si $
		performRemote pcc key afile numcopies mincopies remote ud

performLocal :: PreferredContentChecked -> Key -> AssociatedFile -> NumCopies -> MinCopies -> [VerifiedCopy] -> DroppingUnused -> CommandPerform
performLocal pcc key afile numcopies mincopies preverified ud = lockContentForRemoval key fallback $ \contentlock -> do
	u <- getUUID
	(tocheck, verified) <- verifiableCopies key [u]
	doDrop pcc u (Just contentlock) key afile numcopies mincopies [] (preverified ++ verified) tocheck
		( \proof -> do
			fastDebug "Command.Drop" $ unwords
				[ "Dropping from here"
				, "proof:"
				, show proof
				]
			removeAnnex contentlock
			notifyDrop afile True
			next $ cleanupLocal key ud
		, do 
			notifyDrop afile False
			stop
		)
  where
	-- This occurs when, for example, two files are being dropped
	-- and have the same content. The seek stage checks if the content
	-- is present, but due to buffering, may find it present for the
	-- second file before the first is dropped. If so, nothing remains
	-- to be done except for cleaning up.
	fallback = next $ cleanupLocal key ud

performRemote :: PreferredContentChecked -> Key -> AssociatedFile -> NumCopies -> MinCopies -> Remote -> DroppingUnused -> CommandPerform
performRemote pcc key afile numcopies mincopies remote ud = do
	-- Filter the uuid it's being dropped from out of the lists of
	-- places assumed to have the key, and places to check.
	(tocheck, verified) <- verifiableCopies key [uuid]
	doDrop pcc uuid Nothing key afile numcopies mincopies [uuid] verified tocheck
		( \proof -> do 
			fastDebug "Command.Drop" $ unwords
				[ "Dropping from remote"
				, show remote
				, "proof:"
				, show proof
				]
			ok <- Remote.action (Remote.removeKey remote key)
			next $ cleanupRemote key remote ud ok
		, stop
		)
  where
	uuid = Remote.uuid remote

cleanupLocal :: Key -> DroppingUnused -> CommandCleanup
cleanupLocal key ud = do
	logStatus key (dropStatus ud)
	return True

cleanupRemote :: Key -> Remote -> DroppingUnused -> Bool -> CommandCleanup
cleanupRemote key remote ud ok = do
	when ok $
		Remote.logStatus remote key (dropStatus ud)
	return ok

{- Set when the user explicitly chose to operate on unused content.
 - Presumably the user still expects the last git-annex unused to be
 - correct at this point. -}
newtype DroppingUnused = DroppingUnused Bool

{- When explicitly dropping unused content, mark the key as dead, at least
 - in the repository it was dropped from. It may still be in other
 - repositories, and will not be treated as dead until dropped from all of
 - them. -}
dropStatus :: DroppingUnused -> LogStatus
dropStatus (DroppingUnused False) = InfoMissing
dropStatus (DroppingUnused True) = InfoDead

{- Before running the dropaction, checks specified remotes to
 - verify that enough copies of a key exist to allow it to be
 - safely removed (with no data loss).
 -
 - --force overrides and always allows dropping.
 -}
doDrop
	:: PreferredContentChecked
	-> UUID
	-> Maybe ContentRemovalLock
	-> Key
	-> AssociatedFile
	-> NumCopies
	-> MinCopies
	-> [UUID]
	-> [VerifiedCopy]
	-> [UnVerifiedCopy]
	-> (Maybe SafeDropProof -> CommandPerform, CommandPerform)
	-> CommandPerform
doDrop pcc dropfrom contentlock key afile numcopies mincopies skip preverified check (dropaction, nodropaction) = 
	ifM (Annex.getState Annex.force)
		( dropaction Nothing
		, ifM (checkRequiredContent pcc dropfrom key afile)
			( verifyEnoughCopiesToDrop nolocmsg key 
				contentlock numcopies mincopies
				skip preverified check
					(dropaction . Just)
					(forcehint nodropaction)
			, stop
			)
		)
  where
	nolocmsg = "Rather than dropping this file, try using: git annex move"
	forcehint a = do
		showLongNote "(Use --force to override this check, or adjust numcopies.)"
		a

{- Checking preferred content also checks required content, so when
 - auto mode causes preferred content to be checked, it's redundant
 - for checkRequiredContent to separately check required content, and
 - providing this avoids that extra work. -}
newtype PreferredContentChecked = PreferredContentChecked Bool

checkRequiredContent :: PreferredContentChecked -> UUID -> Key -> AssociatedFile -> Annex Bool
checkRequiredContent (PreferredContentChecked True) _ _ _ = return True
checkRequiredContent (PreferredContentChecked False) u k afile =
	checkDrop isRequiredContent False (Just u) (Just k) afile Nothing >>= \case
		Nothing -> return True
		Just afile' -> do
			if afile == afile'
				then showLongNote "That file is required content. It cannot be dropped!"
				else showLongNote $ "That file has the same content as another file"
					++ case afile' of
						AssociatedFile (Just f) -> " (" ++ fromRawFilePath f ++ "),"
						AssociatedFile Nothing -> ""
					++ " which is required content. It cannot be dropped!"
			showLongNote "(Use --force to override this check, or adjust required content configuration.)"
			return False

{- In auto mode, only runs the action if there are enough
 - copies on other semitrusted repositories. -}
checkDropAuto :: Bool -> Maybe Remote -> AssociatedFile -> Key -> (NumCopies -> MinCopies -> CommandStart) -> CommandStart
checkDropAuto automode mremote afile key a =
	go =<< getSafestNumMinCopies afile key
  where
	go (numcopies, mincopies)
		| automode = do
			locs <- Remote.keyLocations key
			uuid <- getUUID
			let remoteuuid = fromMaybe uuid $ Remote.uuid <$> mremote
			locs' <- trustExclude UnTrusted $ filter (/= remoteuuid) locs
			if NumCopies (length locs') >= numcopies
				then a numcopies mincopies
				else stop
		| otherwise = a numcopies mincopies
