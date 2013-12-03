{-# LANGUAGE DeriveGeneric #-}
module Paxos.Message where

import Data.Serialize
import GHC.Generics

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

data Message = Message Int InstanceMessage 
             deriving (Show, Generic)

instance Serialize Message

