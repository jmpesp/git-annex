{- Backends for git-remote-annex.
 -
 - GITBUNDLE keys store git bundles
 - GITMANIFEST keys store ordered lists of GITBUNDLE keys
 -
 - Copyright 2024 Joey Hess <id@joeyh.name>
 -
 - Licensed under the GNU AGPL version 3 or higher.
 -}

{-# LANGUAGE OverloadedStrings #-}

module Backend.GitRemoteAnnex (
	backends,
	genGitBundleKey,
	genManifestKey,
	isGitRemoteAnnexKey,
) where

import Annex.Common
import Types.Key
import Types.Backend
import Utility.Hash
import Utility.Metered
import qualified Backend.Hash as Hash

import qualified Data.ByteString.Short as S
import qualified Data.ByteString.Char8 as B8

backends :: [Backend]
backends = [gitbundle, gitmanifest]

gitbundle :: Backend
gitbundle = Backend
	{ backendVariety = GitBundleKey
	, genKey = Nothing
	-- ^ Not provided because these keys can only be generated by 
	-- git-remote-annex.
	, verifyKeyContent = Just $ Hash.checkKeyChecksum sameCheckSum hash
	, verifyKeyContentIncrementally = Just (liftIO . incrementalVerifier)
	, canUpgradeKey = Nothing
	, fastMigrate = Nothing
	, isStableKey = const True
	, isCryptographicallySecure = Hash.cryptographicallySecure hash
	, isCryptographicallySecureKey = const $ pure $
		Hash.cryptographicallySecure hash
	}

gitmanifest :: Backend
gitmanifest = Backend
	{ backendVariety = GitManifestKey
	, genKey = Nothing
	, verifyKeyContent = Nothing
	, verifyKeyContentIncrementally = Nothing
	, canUpgradeKey = Nothing
	, fastMigrate = Nothing
	, isStableKey = const True
	, isCryptographicallySecure = False
	, isCryptographicallySecureKey = const $ pure False
	}

-- git bundle keys use the sha256 hash.
hash :: Hash.Hash
hash = Hash.SHA2Hash (HashSize 256)

incrementalVerifier :: Key -> IO IncrementalVerifier
incrementalVerifier = 
	mkIncrementalVerifier sha2_256_context "checksum" . sameCheckSum

sameCheckSum :: Key -> String -> Bool
sameCheckSum key s = s == expected
  where
	-- The checksum comes after a UUID.
	expected = reverse $ takeWhile (/= '-') $ reverse $
		decodeBS $ S.fromShort $ fromKey keyName key

genGitBundleKey :: UUID -> RawFilePath -> MeterUpdate -> Annex Key
genGitBundleKey remoteuuid file meterupdate = do
	filesize <- liftIO $ getFileSize file
	s <- Hash.hashFile hash file meterupdate
	return $ mkKey $ \k -> k
		{ keyName = S.toShort $ fromUUID remoteuuid <> "-" <> encodeBS s
		, keyVariety = GitBundleKey
		, keySize = Just filesize
		}

genManifestKey :: UUID -> Key
genManifestKey u = mkKey $ \kd -> kd
	{ keyName = S.toShort (fromUUID u)
	, keyVariety = GitManifestKey
	}

{- Is the key a manifest or bundle key that belongs to the special remote
 - with this uuid? -}
isGitRemoteAnnexKey :: UUID -> Key -> Bool
isGitRemoteAnnexKey u k = 
	case fromKey keyVariety k of
		GitBundleKey -> sameuuid $ \b ->
			-- Remove the checksum that comes after the UUID.
			let b' = B8.dropWhileEnd (/= '-') b
			in B8.take (B8.length b' - 1) b'
		GitManifestKey -> sameuuid id
		_ -> False
  where
	sameuuid f = fromUUID u == f (S.fromShort (fromKey keyName k))
