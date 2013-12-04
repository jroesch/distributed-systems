{-# LANGUAGE DeriveGeneric, TupleSections #-}
module Paxos.Directory.Remote 
  ( Directory,
    size,
    Process,
    Pid,
    mkDirectory,
    plookup,
    send,
    receive,
    broadcast
  ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan as C
import Control.Concurrent.MVar
import Control.Monad
import Data.Functor ((<$>))
import qualified Data.Map as M
import Data.Serialize
import GHC.Generics
import System.Log.Logger
import qualified Paxos.Remote.Channel as R
import Paxos.Message (Message)

type Pid = Int

data Process = Process Pid (R.Chan RemoteMessage)

data RemoteMessage = APid Pid 
                   | AMessage Message 
                   deriving (Show, Generic)

instance Serialize RemoteMessage
  
instance Show Process where
  show (Process pid _) = "Process " ++ show pid

type Config = [(Pid, String, Int)]
type Directory = MVar (C.Chan RemoteMessage, M.Map Pid (MVar Process))

-- need help here
mkDirectory :: Int -> Pid -> Config -> IO Directory
mkDirectory port this config = do
    reg <- R.channelRegistry
    mailbox <- C.newChan
    dir <- newMVar (mailbox, M.empty)
    forkIO $ R.startChannelService port reg (handler dir) -- other processes will start to fill my slots
    let connectList = filter ((> this) . first) config
    forM_ connectList $ \(pid, h, p) -> do
      rawChan <- R.newChan h p
      R.writeChan rawChan (APid this)
      process <- newMVar $ (Process pid rawChan) 
      modifyMVar_ dir $ \(chan, x) -> return $ (chan, M.insert pid process x)
      forkIO $ forever $ do -- have thread dequeue values into mailbox
        value <- R.readChan rawChan
        C.writeChan mailbox value
      return ()
    return dir
  where handler dir chan = modifyMVar_ dir $ \(mailbox, d) -> do
          APid pid <- R.readChan chan
          if pid >= this
            then error "Something is going with the connection process wrong."
            else do
              forkIO $ forever $ do
                value <- R.readChan chan
                C.writeChan mailbox value
              p <- newMVar (Process pid chan)
              return $ (mailbox, M.insert pid p d)
        first (x, _, _) = x

plookup :: Directory -> Pid -> IO Process
plookup mdir pid = do
    (_, dir) <- readMVar mdir
    case pid `M.lookup` dir of
      Nothing -> error $ "NO PID #YOLO " ++ show pid
      Just v  -> readMVar v

send :: Directory -> Pid -> Message -> IO ()
send dir pid msg = do
    (Process _ chan) <- plookup dir pid
    R.writeChan chan (AMessage msg)
    debugM "paxos.message.send" (show (pid, msg))

receive :: Directory -> IO Message
receive mdir = do
    (chan, dir) <- readMVar mdir
    c <- C.readChan chan 
    debugM "paxos.message.receive" $ "receiving message " ++ show c
    case c of
      AMessage m -> return m
      APid _     -> error "fucking pid"

broadcast :: Directory -> Message -> IO ()
broadcast d m = do
    (mailbox, dir) <- readMVar d
    ps <- mapM readMVar $ M.elems dir
    C.writeChan mailbox $ AMessage m
    forM_ ps $
      \(Process _ chan) -> (R.writeChan chan $ AMessage m)
    debugM "paxos.message.recieve" $ "broadcasting " ++ show m


size :: Directory -> IO Int
size dir = readMVar dir >>= return . M.size . snd

debugIO :: String -> String -> IO a -> IO a
debugIO name msg action = do
    r <- action
    debugM name msg
    return r
