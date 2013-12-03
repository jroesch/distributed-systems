{-# LANGUAGE DeriveGeneric, DefaultSignatures, BangPatterns, GADTs, EmptyDataDecls, OverloadedStrings, ScopedTypeVariables #-}
module Paxos.Remote.Channel (
   Chan,
   hostname, port,
   ChannelRegistry,
   newChan,
   writeChan,
   readChan,
   channelRegistry,
   startChannelService,
   hRead,
   hWrite
  ) where

import Control.Concurrent (forkIO)
import qualified Control.Concurrent.Chan as C
import Control.Concurrent.MVar
import Control.Monad
import Control.Monad.Trans (lift)
import Control.Monad.Trans.Either
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import Data.Functor ((<$>))
import Data.IORef
import Data.Serialize
import Data.Serialize.Get
import Data.Word
import qualified Data.Array as A
import Data.Array ((!))
import GHC.IO.Handle
import GHC.Generics
import Network
import System.Log.Logger
import Debug.Trace

-- | Channel type with two GADT constructors representing locality of
-- channels.
data Chan a where
    MkChan :: Connection -> (C.Chan a) -> Chan a

-- | Message type for opening a channel.
data ChannelOp a = New
                 | Write a
                 | Close
                 deriving (Show, Eq, Generic)

instance Serialize a => Serialize (ChannelOp a)

-- | Represents a connection to a remote channel.
data Connection = Connection !ConnectionInfo !Handle deriving (Eq, Show)

-- | Contains the connection info and channel slot.
data ConnectionInfo = ConnectionInfo !String !PortNumber !Int deriving (Show, Eq, Generic)

hostname :: Chan a -> String
hostname (MkChan (Connection (ConnectionInfo h _ _) _) _) = h

port :: Chan a -> PortNumber
port (MkChan (Connection (ConnectionInfo _ p _) _) _) = p

instance Serialize ConnectionInfo

instance Serialize PortNumber where
  get = do
    word <- getWord32be
    return $ fromIntegral word

  put p = do
    putWord32be $ fromIntegral p

-- | A global registry for open channels.
type ChannelRegistry a = (MVar (ChannelData a))

-- | Channel data that keeps track of free slots, and an array of channels.
data ChannelData a = ChannelData ![Int] (A.Array Int (MVar (C.Chan a)))

newChan :: (Serialize a) => String -> Int -> IO (Chan a)
newChan h p = connectToProcess h p New

writeChan :: (Serialize a) => Chan a -> a -> IO ()
writeChan (MkChan (Connection _ handle) _) v = hWrite handle (Write v)

readChan :: (Serialize a) => Chan a -> IO a
readChan (MkChan _ chan) = C.readChan chan

closeChan :: Chan a -> IO ()
closeChan (MkChan (Connection _ handle) _) = hClose handle

-- | Start the channel service which allows remote processes to open
-- a channel.
startChannelService :: forall a. (Serialize a, Show a) => Int -> ChannelRegistry a -> (Chan a -> IO ()) -> IO ()
startChannelService port reg handler = do
  socket <- listenOn $ PortNumber $ fromIntegral port
  forever $ do
    (handle, hname, port) <- accept socket
    forkIO $ do
      new :: (ChannelOp a) <- hRead handle      
      case new of
        New -> do
          (slot, chan) <- allocateChannel reg
          hWrite handle slot
          putStrLn "Opened new Channel"
          let info = ConnectionInfo hname port slot
              ch = MkChan (Connection info handle) chan -- build our chan
          handler ch -- pass to handler
          forever $ do -- loop reading values from handle and writing to channel
            msg <- hRead handle
            case msg of
              Write v -> C.writeChan chan v
              Close -> freeChannel reg slot
              x@_ -> error $ show x
        _ -> error "not sure what to do here"
    
-- | Connect to remote process given hostname and port number and channel
-- mode.
connectToProcess :: (Serialize a) => String -> Int -> ChannelOp a -> IO (Chan a) -- fix portnumber buissness
connectToProcess host port mode = do 
  putStrLn "Before Connect!"
  handle <- connectTo host (PortNumber $ fromIntegral port) -- open
  putStrLn "After Connect!"
  hWrite handle mode
  slot <- hRead handle
  let conn = Connection (ConnectionInfo host (fromIntegral port) slot) handle
  chan <- C.newChan -- loop here and add messages to queue
  forkIO $ forever $ do
    write <- hRead handle
    case write of
      Write v -> C.writeChan chan v
      _       -> error "programmer error"
  return $ MkChan conn chan

-- | A registry for open channels.
channelRegistry :: IO (ChannelRegistry a)
channelRegistry = do
  mvars <- mapM (\_ -> newEmptyMVar) [0..99]
  let chanArray = A.listArray (0, 99) mvars 
  newMVar (ChannelData [0..99] chanArray)

-- | Allocate a channel in the channel registry, the return is a pair of 
-- the channel descriptor and the channel itself.
allocateChannel :: ChannelRegistry a -> IO (Int, (C.Chan a))
allocateChannel mvar = do
  registry <- takeMVar mvar
  case registry of
    (ChannelData [] array) ->
      error "No more avalible channels"
    (ChannelData (e:es) array) -> do
      let cvar = array ! e
      chan <- C.newChan
      putMVar cvar chan
      putMVar mvar (ChannelData es array)
      return (e, chan)

-- | Lookup a channel based on its channel descriptor.
lookupChannel :: ChannelRegistry a -> Int -> IO (C.Chan a)
lookupChannel mvar e = do
  cr @ (ChannelData _ array) <- readMVar mvar
  let cvar = array ! e
  chan <- readMVar cvar
  return chan

-- | Free a channel from the channel registry.
freeChannel :: ChannelRegistry a -> Int -> IO ()
freeChannel mvar e = do
  registry <- takeMVar mvar
  case registry of
    (ChannelData es array) -> do
      let cvar = array ! e
      _ <- takeMVar cvar
      putMVar mvar (ChannelData (e:es) array)

-- | Reads a value from a Handle in the form of a strict ByteString.
hRead :: (Serialize a) => Handle -> IO a
hRead h = execE $ do
  sizeBytes <- lift $ B.hGet h 8
  size <- hoistEither $ (decode sizeBytes :: Either String Int)
  dat <- lift $ B.hGet h size
  (hoistEither $ decode dat)

-- | Writes a value's length, followed by the value itself to a Handle.
hWrite :: (Serialize a) => Handle -> a -> IO ()
hWrite h val = 
  let msg = encode val
      len = encode $ (B.length msg)
  in B.hPut h $ B.append len msg

-- | Runs an EitherT to completion or forces an exception.
execE :: (Functor m) => EitherT String m a -> m a
execE e = let me = runEitherT e
              in fmap forceErr me
  where forceErr r = case r of
          Left e   -> error $ show e
          Right r' -> r'

