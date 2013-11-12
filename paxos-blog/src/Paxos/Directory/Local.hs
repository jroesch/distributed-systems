{-# LANGUAGE TupleSections #-}
module Paxos.Directory.Local 
  ( Directory,
    Process,
    Pid,
    mkDirectory,
    plookup,
    send,
    receive,
    broadcast
  ) where

import qualified Control.Concurrent.Chan as C
import Data.Functor ((<$>))
import qualified Data.Map as M
import Paxos.Message (Message)
import System.Log.Logger

type Pid = Int

data Process = Process Pid (C.Chan Message) deriving (Eq)

instance Show Process where
  show (Process pid _) = "Process " ++ show pid

type Directory = M.Map Pid Process

mkDirectory :: [Pid] -> IO Directory
mkDirectory ps = do
    pairs <- sequence $ zipWith (\p -> fmap (p,)) ps $ map mkProcess ps
    return $ M.fromList pairs
  where mkProcess pid = (Process pid) <$> C.newChan
        
plookup :: Directory -> Pid -> Process
plookup dir pid = case pid `M.lookup` dir of
  Nothing -> error "NO PID #YOLO"
  Just v  -> v

send :: Directory -> Pid -> Message -> IO ()
send dir pid msg = 
  let p @ (Process _ chan) = plookup dir pid in
    debugIO title (show p) $ C.writeChan chan msg
  where title = "paxos.message.send"

receive :: Process -> IO Message
receive p @ (Process _ chan) = debugIO title (show p) $ C.readChan chan
  where title = "paxos.message.receive"

broadcast :: Directory -> Message -> IO ()
broadcast d m = mapM_ receive $ M.elems d

debugIO :: String -> String -> IO a -> IO a
debugIO name msg action = do
    r <- action
    debugM name msg
    return r
