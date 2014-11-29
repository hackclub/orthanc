{-# LANGUAGE TemplateHaskell, DeriveGeneric, DeriveDataTypeable, UnicodeSyntax #-}

import Control.Distributed.Process
import Control.Distributed.Process.Backend.SimpleLocalnet
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node
import Control.Monad (forever, forM_, sequence)
import Data.Binary
import Data.Maybe
import Data.Typeable
import GHC.Generics (Generic)
import qualified Github.Users as Github
import qualified Github.Data.Definitions as Github
import System.Environment (getArgs)

replyBack :: (ProcessId, String) -> Process ()
replyBack (sender, msg) = send sender msg

logMessage :: String -> Process ()
logMessage msg = say $ "handling " ++ msg

data GithubProfile = GithubProfile { username :: String
					, name :: Maybe String
					, email :: Maybe String
	} deriving (Show, Generic, Typeable)

instance Binary GithubProfile

analyzeGithub :: String -> IO (Either String GithubProfile)
analyzeGithub username = do
	r <- Github.userInfoFor username
	return $ case r of
		Left e -> Left $ "Error"
		Right uinfo -> Right $ GithubProfile {username=username
							, name=Github.detailedOwnerName uinfo
							, email=Github.detailedOwnerEmail uinfo}

slave :: (ProcessId, ProcessId) -> Process ()
slave (master, workQueue) = do
		us <- getSelfPid
		go us
	where
		go us = do
			send workQueue us
			receiveWait
				[ match $ \nm -> liftIO(analyzeGithub nm) >>= send master >> go us
				, match $ \() -> return ()
				]

remotable ['slave]

accProfiles :: Int -> Process [Either String GithubProfile]
accProfiles = go []
	where
		go :: [Either String GithubProfile] -> Int -> Process [Either String GithubProfile]
		go acc 0 = return $ reverse acc
		go acc n = do
			m <- expect
			go (m : acc) (n - 1)

master :: [String] -> [NodeId] -> Process [Either String GithubProfile]
master usernames slaves = do
	us <- getSelfPid
	workQueue <- spawnLocal $ do
		sequence $ map (\u -> expect >>= \them->send them u) usernames
		forever $ expect >>= \pid -> send pid ()

	forM_ slaves $ \nid -> spawn nid ($(mkClosure 'slave) (us, workQueue))
	accProfiles $ length usernames

rtable :: RemoteTable
rtable = __remoteTable initRemoteTable

main :: IO ()
main = do
	args <- getArgs

	case args of
		("master" : host : port : usernames) -> do
			backend <- initializeBackend host port rtable
			startMaster backend $ \slaves -> do
				result <- master usernames slaves
				liftIO $ print result

		["slave", host, port] -> do
			backend <- initializeBackend host port rtable
			startSlave backend

		_ -> putStrLn "Bad args"
