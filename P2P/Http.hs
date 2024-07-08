{- P2P protocol over HTTP
 -
 - https://git-annex.branchable.com/design/p2p_protocol_over_http/
 -
 - Copyright 2024 Joey Hess <id@joeyh.name>
 -
 - Licensed under the GNU AGPL version 3 or higher.
 -}

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}

module P2P.Http where

import Annex.Common
import qualified P2P.Protocol as P2P
import Utility.Base64
import Utility.MonotonicClock

import Servant
import Servant.Client.Streaming
import qualified Servant.Types.SourceT as S
import Network.HTTP.Client (defaultManagerSettings, newManager)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString as B
import Text.Read (readMaybe)
import Data.Aeson hiding (Key)
import Control.DeepSeq
import Control.Concurrent
import Control.Concurrent.STM
import GHC.Generics

type P2PHttpAPI
	= "git-annex" :> "v3" :> "key" :> CaptureKey
		:> GetAPI '[DataLengthHeader]
	:<|> "git-annex" :> "v2" :> "key" :> CaptureKey
		:> GetAPI '[DataLengthHeader]
	:<|> "git-annex" :> "v1" :> "key" :> CaptureKey
		:> GetAPI '[DataLengthHeader]
	:<|> "git-annex" :> "v0" :> "key" :> CaptureKey
		:> GetAPI '[]
	:<|> "git-annex" :> "v3" :> "checkpresent" :> CheckPresentAPI
	:<|> "git-annex" :> "v2" :> "checkpresent" :> CheckPresentAPI
	:<|> "git-annex" :> "v1" :> "checkpresent" :> CheckPresentAPI
	:<|> "git-annex" :> "v0" :> "checkpresent" :> CheckPresentAPI
	:<|> "git-annex" :> "v3" :> "remove" :> RemoveAPI RemoveResultPlus
	:<|> "git-annex" :> "v2" :> "remove" :> RemoveAPI RemoveResultPlus
	:<|> "git-annex" :> "v1" :> "remove" :> RemoveAPI RemoveResult
	:<|> "git-annex" :> "v0" :> "remove" :> RemoveAPI RemoveResult
	:<|> "git-annex" :> "v3" :> "remove-before" :> RemoveBeforeAPI
	:<|> "git-annex" :> "v3" :> "gettimestamp" :> GetTimestampAPI
	:<|> "git-annex" :> "v3" :> "put" :> DataLengthHeader
		:> PutAPI PutResultPlus
	:<|> "git-annex" :> "v2" :> "put" :> DataLengthHeader
		:> PutAPI PutResultPlus
	:<|> "git-annex" :> "v1" :> "put" :> DataLengthHeader
		:> PutAPI PutResult
	:<|> "git-annex" :> "v0" :> "put"
		:> PutAPI PutResult
	:<|> "git-annex" :> "v3" :> "putoffset"
		:> PutOffsetAPI PutOffsetResultPlus
	:<|> "git-annex" :> "v2" :> "putoffset"
		:> PutOffsetAPI PutOffsetResultPlus
	:<|> "git-annex" :> "v1" :> "putoffset"
		:> PutOffsetAPI PutOffsetResult
	:<|> "git-annex" :> "v3" :> "lockcontent" :> LockContentAPI
	:<|> "git-annex" :> "v2" :> "lockcontent" :> LockContentAPI
	:<|> "git-annex" :> "v1" :> "lockcontent" :> LockContentAPI
	:<|> "git-annex" :> "v0" :> "lockcontent" :> LockContentAPI
	:<|> "git-annex" :> "v3" :> "keeplocked" :> KeepLockedAPI
	:<|> "git-annex" :> "v2" :> "keeplocked" :> KeepLockedAPI
	:<|> "git-annex" :> "v1" :> "keeplocked" :> KeepLockedAPI
	:<|> "git-annex" :> "v0" :> "keeplocked" :> KeepLockedAPI
	:<|> "git-annex" :> "key" :> CaptureKey :> GetAPI '[]

p2pHttpAPI :: Proxy P2PHttpAPI
p2pHttpAPI = Proxy

p2pHttpApp :: Application
p2pHttpApp = serve p2pHttpAPI serveP2pHttp

serveP2pHttp :: Server P2PHttpAPI
serveP2pHttp
	= serveGet
	:<|> serveGet
	:<|> serveGet
	:<|> serveGet0
	:<|> serveCheckPresent
	:<|> serveCheckPresent
	:<|> serveCheckPresent
	:<|> serveCheckPresent
	:<|> serveRemove id
	:<|> serveRemove id
	:<|> serveRemove dePlus
	:<|> serveRemove dePlus
	:<|> serveRemoveBefore
	:<|> serveGetTimestamp
	:<|> servePut id
	:<|> servePut id
	:<|> servePut dePlus
	:<|> servePut dePlus Nothing
	:<|> servePutOffset id
	:<|> servePutOffset id
	:<|> servePutOffset dePlus
	:<|> serveLockContent
	:<|> serveLockContent
	:<|> serveLockContent
	:<|> serveLockContent
	:<|> serveKeepLocked
	:<|> serveKeepLocked
	:<|> serveKeepLocked
	:<|> serveKeepLocked
	:<|> serveGet0

type GetAPI headers
	= ClientUUID Optional
	:> ServerUUID Optional
	:> BypassUUIDs
	:> AssociatedFileParam
	:> OffsetParam
	:> StreamGet NoFraming OctetStream
		(Headers headers (SourceIO B.ByteString))

serveGet
	:: B64Key
	-> Maybe (B64UUID ClientSide)
	-> Maybe (B64UUID ServerSide)
	-> [B64UUID Bypass]
	-> Maybe B64FilePath
	-> Maybe Offset
	-> Handler (Headers '[DataLengthHeader] (S.SourceT IO B.ByteString))
serveGet = undefined

serveGet0
	:: B64Key
	-> Maybe (B64UUID ClientSide)
	-> Maybe (B64UUID ServerSide)
	-> [B64UUID Bypass]
	-> Maybe B64FilePath
	-> Maybe Offset
	-> Handler (Headers '[] (S.SourceT IO B.ByteString))
serveGet0 = undefined

clientGet
	:: P2P.ProtocolVersion
	-> B64Key
	-> Maybe (B64UUID ClientSide)
	-> Maybe (B64UUID ServerSide)
	-> [B64UUID Bypass]
	-> Maybe B64FilePath
	-> Maybe Offset
	-> ClientM (Headers '[DataLengthHeader] (S.SourceT IO B.ByteString))
clientGet (P2P.ProtocolVersion ver) k cu su bypass af o = case ver of
	3 -> v3 k cu su bypass af o
	2 -> v2 k cu su bypass af o
	1 -> error "XXX" -- TODO v1  
	0 -> error "XXX" -- TODO v0
	_ -> error "unsupported protocol version"
  where
	_ :<|> v3 :<|> v2 :<|> v1 :<|> v0 :<|> _ = client p2pHttpAPI

type CheckPresentAPI
	= KeyParam
	:> ClientUUID Required
	:> ServerUUID Required
	:> BypassUUIDs
	:> Post '[JSON] CheckPresentResult

serveCheckPresent
	:: B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> Handler CheckPresentResult
serveCheckPresent = undefined

clientCheckPresent
	:: P2P.ProtocolVersion
	-> B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> ClientM CheckPresentResult
clientCheckPresent (P2P.ProtocolVersion ver) = case ver of
	3 -> v3
	2 -> v2
	1 -> v1
	0 -> v0
	_ -> error "unsupported protocol version"
  where
	_ :<|> _ :<|> _ :<|> _ :<|>
		v3 :<|> v2 :<|> v1 :<|> v0 :<|> _ = client p2pHttpAPI

type RemoveAPI result
	= KeyParam
	:> ClientUUID Required
	:> ServerUUID Required
	:> BypassUUIDs
	:> Post '[JSON] result
	
serveRemove
	:: (RemoveResultPlus -> t)
	-> B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> Handler t
serveRemove = undefined

clientRemove
	:: P2P.ProtocolVersion
	-> B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> ClientM RemoveResultPlus
clientRemove (P2P.ProtocolVersion ver) k cu su bypass = case ver of
	3 -> v3 k cu su bypass
	2 -> v2 k cu su bypass
	1 -> plus <$> v1 k cu su bypass
	0 -> plus <$> v0 k cu su bypass
	_ -> error "unsupported protocol version"
  where
	_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		v3 :<|> v2 :<|> v1 :<|> v0 :<|> _ = client p2pHttpAPI
	
type RemoveBeforeAPI
	= KeyParam
	:> ClientUUID Required
	:> ServerUUID Required
	:> BypassUUIDs
	:> QueryParam' '[Required] "timestamp" Timestamp
	:> Post '[JSON] RemoveResult

serveRemoveBefore
	:: B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> Timestamp
	-> Handler RemoveResult
serveRemoveBefore = undefined

clientRemoveBefore
	:: P2P.ProtocolVersion
	-> B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> Timestamp
	-> ClientM RemoveResult
clientRemoveBefore (P2P.ProtocolVersion ver) = case ver of
	3 -> v3
	_ -> error "unsupported protocol version"
  where
	_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		v3 :<|> _ = client p2pHttpAPI


type GetTimestampAPI
	= ClientUUID Required
	:> ServerUUID Required
	:> BypassUUIDs
	:> Post '[JSON] GetTimestampResult

serveGetTimestamp
	:: B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> Handler GetTimestampResult
serveGetTimestamp = undefined

clientGetTimestamp
	:: P2P.ProtocolVersion
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> ClientM GetTimestampResult
clientGetTimestamp (P2P.ProtocolVersion ver) = case ver of
	3 -> v3
	_ -> error "unsupported protocol version"
  where
	_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|>
		v3 :<|> _ = client p2pHttpAPI

type PutAPI result
	= KeyParam
	:> ClientUUID Required
	:> ServerUUID Required
	:> BypassUUIDs
	:> AssociatedFileParam
	:> OffsetParam
	:> Header' '[Required] "X-git-annex-data-length" DataLength
	:> StreamBody NoFraming OctetStream (SourceIO B.ByteString)
	:> Post '[JSON] result

servePut
	:: (PutResultPlus -> t)
	-> Maybe Integer
	-> B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> Maybe B64FilePath
	-> Maybe Offset
	-> DataLength
	-> S.SourceT IO B.ByteString
	-> Handler t
servePut = undefined

clientPut
	:: P2P.ProtocolVersion
	-> Maybe Integer
	-> B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> Maybe B64FilePath
	-> Maybe Offset
	-> DataLength
	-> S.SourceT IO B.ByteString
	-> ClientM PutResultPlus
clientPut (P2P.ProtocolVersion ver) sz k cu su bypass af o l src = case ver of
	3 -> v3 sz k cu su bypass af o l src
	2 -> v2 sz k cu su bypass af o l src
	1 -> plus <$> v1 sz k cu su bypass af o l src
	0 -> plus <$> v0 k cu su bypass af o l src
	_ -> error "unsupported protocol version"
  where
	_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|>
		_ :<|>
		v3 :<|> v2 :<|> v1 :<|> v0 :<|> _ = client p2pHttpAPI

type PutOffsetAPI result
	= KeyParam
	:> ClientUUID Required
	:> ServerUUID Required
	:> BypassUUIDs
	:> Post '[JSON] result

servePutOffset
	:: (PutOffsetResultPlus -> t)
	-> B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> Handler t
servePutOffset = undefined

clientPutOffset
	:: P2P.ProtocolVersion
	-> B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> ClientM PutOffsetResultPlus
clientPutOffset (P2P.ProtocolVersion ver) = case ver of
	3 -> v3
	2 -> v2
	_ -> error "unsupported protocol version"
  where
	_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|>
		_ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		v3 :<|> v2 :<|> _ = client p2pHttpAPI

type LockContentAPI
	= KeyParam
	:> ClientUUID Required
	:> ServerUUID Required
	:> BypassUUIDs
	:> Post '[JSON] LockResult

serveLockContent
	:: B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> Handler LockResult
serveLockContent = undefined

clientLockContent
	:: P2P.ProtocolVersion
	-> B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> ClientM LockResult
clientLockContent (P2P.ProtocolVersion ver) = case ver of
	3 -> v3
	2 -> v2
	1 -> v1
	0 -> v0
	_ -> error "unsupported protocol version"
  where
	_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|>
		_ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|>
		v3 :<|> v2 :<|> v1 :<|> v0 :<|> _ = client p2pHttpAPI

type KeepLockedAPI
	= KeyParam
	:> ClientUUID Required
	:> ServerUUID Required
	:> BypassUUIDs
	:> Header "Connection" ConnectionKeepAlive
	:> Header "Keep-Alive" KeepAlive
	:> StreamBody NewlineFraming JSON (SourceIO UnlockRequest)
	:> Post '[JSON] LockResult

serveKeepLocked
	:: B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> Maybe ConnectionKeepAlive
	-> Maybe KeepAlive
	-> S.SourceT IO UnlockRequest
	-> Handler LockResult
serveKeepLocked k cu su _ _ _ unlockrequeststream = do
	_ <- liftIO $ S.unSourceT unlockrequeststream go
	return (LockResult False)
  where
	go S.Stop = do
		print "lost connection to client, drop lock here" -- XXX TODO
	go (S.Error err) = do
		print ("Error", err)
		print "error, drop lock here" -- XXX TODO
	go (S.Skip s)    = go s
	go (S.Effect ms) = ms >>= go
	go (S.Yield (UnlockRequest False) s) = go s
	go (S.Yield (UnlockRequest True) _) = do
		print ("got unlock request, drop lock here") -- XXX TODO

clientKeepLocked
	:: P2P.ProtocolVersion
	-> B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> Maybe ConnectionKeepAlive
	-> Maybe KeepAlive
	-> S.SourceT IO UnlockRequest
	-> ClientM LockResult
clientKeepLocked (P2P.ProtocolVersion ver) = case ver of
	3 -> v3
	2 -> v2
	1 -> v1
	0 -> v0
	_ -> error "unsupported protocol version"
  where
	_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|>
		_ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|>
		_ :<|> _ :<|> _ :<|> _ :<|>
		v3 :<|> v2 :<|> v1 :<|> v0 :<|> _ = client p2pHttpAPI

clientKeepLocked'
	:: ClientEnv
	-> P2P.ProtocolVersion
	-> B64Key
	-> B64UUID ClientSide
	-> B64UUID ServerSide
	-> [B64UUID Bypass]
	-> TMVar Bool
	-> IO ()
clientKeepLocked' clientenv protover key cu su bypass keeplocked = do
	let cli = clientKeepLocked protover key cu su bypass
		(Just connectionKeepAlive) (Just keepAlive)
		(S.fromStepT unlocksender)
	withClientM cli clientenv $ \case
		Left err  -> throwM err
		Right (LockResult _) ->
			liftIO $ print "end of lock connection to server"
  where
	unlocksender =
		S.Yield (UnlockRequest False) $ S.Effect $ do
			liftIO $ print "sent keep locked request"
			return $ S.Effect $ do
				stilllock <- liftIO $ atomically $ takeTMVar keeplocked
				if stilllock
					then return unlocksender
					else do
						liftIO $ print "sending unlock request"
						return $ S.Yield (UnlockRequest True) S.Stop

testClientLock = do
	mgr <- newManager defaultManagerSettings
	burl <- parseBaseUrl "http://localhost:8080/"
	keeplocked <- newEmptyTMVarIO
	_ <- forkIO $ do
		print "running, press enter to drop lock"
		_ <- getLine
		atomically $ writeTMVar keeplocked False
	clientKeepLocked' (mkClientEnv mgr burl)
		(P2P.ProtocolVersion 3)
		(B64Key (fromJust $ deserializeKey "WORM--foo"))
		(B64UUID (toUUID ("cu" :: String)))
		(B64UUID (toUUID ("su" :: String)))
		[]
		keeplocked

type ClientUUID req = QueryParam' '[req] "clientuuid" (B64UUID ClientSide)

type ServerUUID req = QueryParam' '[req] "serveruuid" (B64UUID ServerSide)

type BypassUUIDs = QueryParams "bypass" (B64UUID Bypass)

type CaptureKey = Capture "key" B64Key

type KeyParam = QueryParam' '[Required] "key" B64Key

type AssociatedFileParam = QueryParam "associatedfile" B64FilePath
	
type OffsetParam = QueryParam "offset" Offset

type DataLengthHeader = Header "X-git-annex-data-length" Integer

-- Phantom types for B64UIID
data ClientSide
data ServerSide
data Bypass
data Plus

-- Keys, UUIDs, and filenames are base64 encoded since Servant uses 
-- Text and so needs UTF-8.
newtype B64Key = B64Key Key
	deriving (Show)

newtype B64UUID t = B64UUID UUID
	deriving (Show, Generic, NFData)

newtype B64FilePath = B64FilePath RawFilePath
	deriving (Show)

newtype DataLength = DataLength Integer
	deriving (Show)

newtype CheckPresentResult = CheckPresentResult Bool
	deriving (Show)

newtype RemoveResult = RemoveResult Bool
	deriving (Show)

data RemoveResultPlus = RemoveResultPlus Bool [B64UUID Plus]
	deriving (Show)

newtype GetTimestampResult = GetTimestampResult Timestamp
	deriving (Show)

newtype PutResult = PutResult Bool
	deriving (Eq, Show)

data PutResultPlus = PutResultPlus Bool [B64UUID Plus]
	deriving (Show)

newtype PutOffsetResult = PutOffsetResult Offset
	deriving (Show)

data PutOffsetResultPlus = PutOffsetResultPlus Offset [B64UUID Plus]
	deriving (Show, Generic, NFData)

newtype Offset = Offset P2P.Offset
	deriving (Show, Generic, NFData)

newtype Timestamp = Timestamp MonotonicTimestamp
	deriving (Show)

newtype LockResult = LockResult Bool
	deriving (Show, Generic, NFData)

newtype UnlockRequest = UnlockRequest Bool
	deriving (Show, Generic, NFData)

newtype ConnectionKeepAlive = ConnectionKeepAlive T.Text

connectionKeepAlive :: ConnectionKeepAlive
connectionKeepAlive = ConnectionKeepAlive "Keep-Alive"

newtype KeepAlive = KeepAlive T.Text

keepAlive :: KeepAlive
keepAlive = KeepAlive "timeout=1200"

instance ToHttpApiData ConnectionKeepAlive where
	toUrlPiece (ConnectionKeepAlive t) = t

instance FromHttpApiData ConnectionKeepAlive where
	parseUrlPiece = Right . ConnectionKeepAlive

instance ToHttpApiData KeepAlive where
	toUrlPiece (KeepAlive t) = t

instance FromHttpApiData KeepAlive where
	parseUrlPiece = Right . KeepAlive

instance ToHttpApiData B64Key where
	toUrlPiece (B64Key k) = TE.decodeUtf8Lenient $
		toB64 (serializeKey' k)

instance FromHttpApiData B64Key where
	parseUrlPiece t = case fromB64Maybe (TE.encodeUtf8 t) of
		Nothing -> Left "unable to base64 decode key"
		Just b -> maybe (Left "key parse error") (Right . B64Key)
			(deserializeKey' b)

instance ToHttpApiData (B64UUID t) where
	toUrlPiece (B64UUID u) = TE.decodeUtf8Lenient $
		toB64 (fromUUID u)

instance FromHttpApiData (B64UUID t) where
	parseUrlPiece t = case fromB64Maybe (TE.encodeUtf8 t) of
		Nothing -> Left "unable to base64 decode UUID"
		Just b -> case toUUID b of
			u@(UUID _) -> Right (B64UUID u)
			NoUUID -> Left "empty UUID"

instance ToHttpApiData B64FilePath where
	toUrlPiece (B64FilePath f) = TE.decodeUtf8Lenient $ toB64 f

instance FromHttpApiData B64FilePath where
	parseUrlPiece t = case fromB64Maybe (TE.encodeUtf8 t) of
		Nothing -> Left "unable to base64 decode filename"
		Just b -> Right (B64FilePath b)

instance ToHttpApiData Offset where
	toUrlPiece (Offset (P2P.Offset n)) = T.pack (show n)

instance FromHttpApiData Offset where
	parseUrlPiece t = case readMaybe (T.unpack t) of
		Nothing -> Left "offset parse error"
		Just n -> Right (Offset (P2P.Offset n))

instance ToHttpApiData Timestamp where
	toUrlPiece (Timestamp (MonotonicTimestamp n)) = T.pack (show n)

instance FromHttpApiData Timestamp where
	parseUrlPiece t = case readMaybe (T.unpack t) of
		Nothing -> Left "timestamp parse error"
		Just n -> Right (Timestamp (MonotonicTimestamp n))

instance ToHttpApiData DataLength where
	toUrlPiece (DataLength n) = T.pack (show n)

instance FromHttpApiData DataLength where
	parseUrlPiece t = case readMaybe (T.unpack t) of
		Nothing -> Left "X-git-annex-data-length parse error"
		Just n -> Right (DataLength n)

instance ToJSON PutResult where
	toJSON (PutResult b) =
		object ["stored" .= b]

instance FromJSON PutResult where
	parseJSON = withObject "PutResult" $ \v -> PutResult
		<$> v .: "stored"

instance ToJSON PutResultPlus where
	toJSON (PutResultPlus b us) = object
		[ "stored" .= b
		, "plusuuids" .= plusList us
		]

instance FromJSON PutResultPlus where
	parseJSON = withObject "PutResultPlus" $ \v -> PutResultPlus
		<$> v .: "stored"
		<*> v .: "plusuuids"

instance ToJSON CheckPresentResult where
	toJSON (CheckPresentResult b) = object
		["present" .= b]

instance FromJSON CheckPresentResult where
	parseJSON = withObject "CheckPresentResult" $ \v -> CheckPresentResult
		<$> v .: "present"

instance ToJSON RemoveResult where
	toJSON (RemoveResult b) = object
		["removed" .= b]

instance FromJSON RemoveResult where
	parseJSON = withObject "RemoveResult" $ \v -> RemoveResult
		<$> v .: "removed"

instance ToJSON RemoveResultPlus where
	toJSON (RemoveResultPlus b us) = object
		[ "removed" .= b
		, "plusuuids" .= plusList us
		]

instance FromJSON RemoveResultPlus where
	parseJSON = withObject "RemoveResultPlus" $ \v -> RemoveResultPlus
		<$> v .: "removed"
		<*> v .: "plusuuids"

instance ToJSON GetTimestampResult where
	toJSON (GetTimestampResult (Timestamp (MonotonicTimestamp t))) = object
		["timestamp" .= t]

instance FromJSON GetTimestampResult where
	parseJSON = withObject "GetTimestampResult" $ \v ->
		GetTimestampResult . Timestamp . MonotonicTimestamp
			<$> v .: "timestamp"

instance ToJSON PutOffsetResult where
	toJSON (PutOffsetResult (Offset (P2P.Offset o))) = object
		["offset" .= o]

instance FromJSON PutOffsetResult where
	parseJSON = withObject "PutOffsetResult" $ \v ->
		PutOffsetResult
			<$> (Offset . P2P.Offset <$> v .: "offset")

instance ToJSON PutOffsetResultPlus where
	toJSON (PutOffsetResultPlus (Offset (P2P.Offset o)) us) = object
		[ "offset" .= o
		, "plusuuids" .= plusList us
		]

instance FromJSON PutOffsetResultPlus where
	parseJSON = withObject "PutOffsetResultPlus" $ \v ->
		PutOffsetResultPlus
			<$> (Offset . P2P.Offset <$> v .: "offset")
			<*> v .: "plusuuids"

instance FromJSON (B64UUID t) where
	parseJSON (String t) = case fromB64Maybe (TE.encodeUtf8 t) of
		Just s -> pure (B64UUID (toUUID s))
		_ -> mempty
	parseJSON _ = mempty

instance ToJSON LockResult where
	toJSON (LockResult v) = object
		["locked" .= v]

instance FromJSON LockResult where
	parseJSON = withObject "LockResult" $ \v -> LockResult
		<$> v .: "locked"

instance ToJSON UnlockRequest where
	toJSON (UnlockRequest v) = object
		["unlock" .= v]

instance FromJSON UnlockRequest where
	parseJSON = withObject "UnlockRequest" $ \v -> UnlockRequest
		<$> v .: "unlock"

plusList :: [B64UUID Plus] -> [String]
plusList = map (\(B64UUID u) -> fromUUID u)

class PlusClass plus unplus where
	dePlus :: plus -> unplus
	plus :: unplus -> plus

instance PlusClass RemoveResultPlus RemoveResult where
	dePlus (RemoveResultPlus b _) = RemoveResult b
	plus (RemoveResult b) = RemoveResultPlus b mempty

instance PlusClass PutResultPlus PutResult where
	dePlus (PutResultPlus b _) = PutResult b
	plus (PutResult b) = PutResultPlus b mempty

instance PlusClass PutOffsetResultPlus PutOffsetResult where
	dePlus (PutOffsetResultPlus o _) = PutOffsetResult o
	plus (PutOffsetResult o) = PutOffsetResultPlus o mempty
