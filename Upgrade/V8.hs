{- git-annex v8 -> v9 upgrade support
 -
 - Copyright 2022 Joey Hess <id@joeyh.name>
 -
 - Licensed under the GNU AGPL version 3 or higher.
 -}

module Upgrade.V8 where

import Annex.Common
import Annex.Content
import Annex.Perms
import Git.ConfigTypes
import Types.RepoVersion

upgrade :: Bool -> Annex Bool
upgrade automatic = do
	unless automatic $
		showAction "v8 to v9"

	{- When core.sharedRepository is set, object files
	 - used to have their write bits set. That can now be removed,
	 - if the user the upgrade is running as has permission to remove
	 - it. (Otherwise, a later fsck will fix up the permissions.) -}
	withShared $ \sr -> case sr of
		GroupShared -> removewrite sr
		AllShared -> removewrite sr
		_ -> return ()

	return True
  where
	newver = Just (RepoVersion 9)

	removewrite sr = do
		ks <- listKeys InAnnex
		forM_ ks $ \k -> do
			obj <- calcRepo (gitAnnexLocation k)
			keystatus <- getKeyStatus k
			case keystatus of
				KeyPresent -> void $ tryIO $
					freezeContent'' sr obj newver
				KeyUnlockedThin -> return ()
				KeyLockedThin -> return ()
				KeyMissing -> return ()