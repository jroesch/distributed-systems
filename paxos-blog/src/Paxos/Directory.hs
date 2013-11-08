{-# LANGUAGE TupleSections #-}
module Paxos.Directory where

import Data.Functor ((<$>))
import Control.Concurrent.Chan
import qualified Data.Map as M
-- import Paxos.BiChan

type Pid = Int
type Message = String 

data Process = Process Pid (Chan Message)

type Directory = M.Map Pid Process

--mkDirectory :: [Pid] -> IO Directory
--mkDirectory ps = sequence $ zipWith (fmap (1,)) $ map mkProcess ps
  --where mkProcess pid = (Process pid) <$> newChan
        
lookup :: Pid -> Process
lookup = undefined



