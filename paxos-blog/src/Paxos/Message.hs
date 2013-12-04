{-# LANGUAGE DeriveGeneric, FlexibleInstances #-}
module Paxos.Message where

import Data.Serialize
import Data.Serialize.Get
import GHC.Generics
import Data.Vector

type Entry = String
type Value = Maybe Entry

newtype Ballot = Ballot (Int, Int) deriving (Show, Eq, Generic)

instance Serialize Ballot

instance Ord Ballot where
  compare (Ballot (a, b)) (Ballot (c, d)) = 
    case compare a c of
      EQ -> compare b d
      o  -> o

data InstanceMessage = Prepare Ballot 
                     | Ack Ballot Ballot Value 
                     | Accept Ballot Entry 
                     | Decide Entry
                     deriving (Show, Eq, Generic)

instance Serialize InstanceMessage

instance Serialize (Vector Value) where
    put = put . toList
    get = do
      a <- getListOf get
      return $ fromList a

data Message = Message Int InstanceMessage
             | Learn Int Int -- we want to come up to speed pid, least unknown
             | Have Int (Vector Value)
             deriving (Show, Generic)

instance Serialize Message

