{- git-annex file locations
 -
 - Copyright 2010 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module Locations (
	gitStateDir,
	stateDir,
	keyFile,
	fileKey,
	gitAnnexLocation,
	annexLocation,
	gitAnnexDir,
	gitAnnexObjectDir,
	gitAnnexTmpDir,
	gitAnnexTmpLocation,
	gitAnnexBadDir,
	gitAnnexUnusedLog,
	isLinkToAnnex,

	prop_idempotent_fileKey
) where

import System.FilePath
import Data.String.Utils
import Data.List
import Bits
import Word
import Data.Hash.MD5

import Types
import qualified GitRepo as Git

{- Conventions:
 -
 - Functions ending in "Dir" should always return values ending with a
 - trailing path separator. Most code does not rely on that, but a few
 - things do. 
 -
 - Everything else should not end in a trailing path sepatator. 
 -
 - Only functions (with names starting with "git") that build a path
 - based on a git repository should return an absolute path.
 - Everything else should use relative paths.
 -}

{- Long-term, cross-repo state is stored in files inside the .git-annex
 - directory, in the git repository's working tree. -}
stateDir :: FilePath
stateDir = addTrailingPathSeparator $ ".git-annex"
gitStateDir :: Git.Repo -> FilePath
gitStateDir repo = addTrailingPathSeparator $ Git.workTree repo </> stateDir

{- The directory git annex uses for local state, relative to the .git
 - directory -}
annexDir :: FilePath
annexDir = addTrailingPathSeparator $ "annex"

{- The directory git annex uses for locally available object content,
 - relative to the .git directory -}
objectDir :: FilePath
objectDir = addTrailingPathSeparator $ annexDir </> "objects"

{- Annexed file's location relative to the .git directory. -}
annexLocation :: Key -> FilePath
annexLocation key = objectDir </> f </> f
	where
		f = keyFile key

{- Annexed file's absolute location in a repository. -}
gitAnnexLocation :: Git.Repo -> Key -> FilePath
gitAnnexLocation r key
	| Git.repoIsLocalBare r = Git.workTree r </> annexLocation key
	| otherwise = Git.workTree r </> ".git" </> annexLocation key

{- The annex directory of a repository. -}
gitAnnexDir :: Git.Repo -> FilePath
gitAnnexDir r
	| Git.repoIsLocalBare r = addTrailingPathSeparator $ Git.workTree r </> annexDir
	| otherwise = addTrailingPathSeparator $ Git.workTree r </> ".git" </> annexDir

{- The part of the annex directory where file contents are stored.
 -}
gitAnnexObjectDir :: Git.Repo -> FilePath
gitAnnexObjectDir r
	| Git.repoIsLocalBare r = addTrailingPathSeparator $ Git.workTree r </> objectDir
	| otherwise = addTrailingPathSeparator $ Git.workTree r </> ".git" </> objectDir

{- .git-annex/tmp/ is used for temp files -}
gitAnnexTmpDir :: Git.Repo -> FilePath
gitAnnexTmpDir r = addTrailingPathSeparator $ gitAnnexDir r </> "tmp"

{- The temp file to use for a given key. -}
gitAnnexTmpLocation :: Git.Repo -> Key -> FilePath
gitAnnexTmpLocation r key = gitAnnexTmpDir r </> keyFile key

{- .git-annex/bad/ is used for bad files found during fsck -}
gitAnnexBadDir :: Git.Repo -> FilePath
gitAnnexBadDir r = addTrailingPathSeparator $ gitAnnexDir r </> "bad"

{- .git/annex/unused is used to number possibly unused keys -}
gitAnnexUnusedLog :: Git.Repo -> FilePath
gitAnnexUnusedLog r = gitAnnexDir r </> "unused"

{- Checks a symlink target to see if it appears to point to annexed content. -}
isLinkToAnnex :: FilePath -> Bool
isLinkToAnnex s = ("/.git/" ++ objectDir) `isInfixOf` s

{- Converts a key into a filename fragment.
 -
 - Escape "/" in the key name, to keep a flat tree of files and avoid
 - issues with keys containing "/../" or ending with "/" etc. 
 -
 - "/" is escaped to "%" because it's short and rarely used, and resembles
 -     a slash
 - "%" is escaped to "&s", and "&" to "&a"; this ensures that the mapping
 -     is one to one.
 - -}
keyFile :: Key -> FilePath
keyFile key = replace "/" "%" $ replace "%" "&s" $ replace "&" "&a"  $ show key

{- Reverses keyFile, converting a filename fragment (ie, the basename of
 - the symlink target) into a key. -}
fileKey :: FilePath -> Key
fileKey file = read $
	replace "&a" "&" $ replace "&s" "%" $ replace "%" "/" file

{- for quickcheck -}
prop_idempotent_fileKey :: String -> Bool
prop_idempotent_fileKey s = k == fileKey (keyFile k)
	where k = read $ "test:" ++ s

{- Given a filename, generates a short directory name to put it in,
 - to do hashing to protect against filesystems that dislike having
 - many items in a single directory. -}
hashDir :: FilePath -> FilePath
hashDir s = take 2 $ abcd_to_dir $ md5 (Str s)

abcd_to_dir :: ABCD -> String
abcd_to_dir (ABCD (a,b,c,d)) = concat $ map display_32bits_as_dir [a,b,c,d]

{- modified version of display_32bits_as_hex from Data.Hash.MD5
 -   Copyright (C) 2001 Ian Lynagh 
 -   License: Either BSD or GPL
 -}
display_32bits_as_dir :: Word32 -> String
display_32bits_as_dir w = trim $ swap_pairs cs
	where 
		-- Need 32 characters to use. To avoid inaverdently making
		-- a real word, use the alphabet without vowels.
		chars = ['0'..'9'] ++ "bcdfghjklnmpqrstvwxyzZ"
		cs = map (\x -> getc $ (shiftR w (6*x)) .&. 31) [0..7]
		getc n = chars !! (fromIntegral n)
		swap_pairs (x1:x2:xs) = x2:x1:swap_pairs xs
		swap_pairs _ = []
		-- Last 2 will always be 00, so omit.
		trim s = take 6 s
