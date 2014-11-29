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

data GithubProfile = GithubProfile {
	id :: Int
	,login :: String
	,email :: Maybe String
	,name :: Maybe String
	,company :: Maybe String
	,publicGists :: Int
	,followers :: Int
	,following :: Int
	,hireable :: Maybe Bool
	,blog :: Maybe String
	,publicRepos :: Int
	,location :: Maybe String
	,url :: String
	,avatarUrl :: String
	} deriving (Show, Generic, Typeable)

instance Binary GithubProfile

analyzeGithub :: String -> IO (Either String GithubProfile)
analyzeGithub username = do
	r <- Github.userInfoFor username
	return $ case r of
		Left e -> Left $ show e
		Right uinfo -> Right $ GithubProfile {
			Main.id=Github.detailedOwnerId uinfo
			,login=Github.detailedOwnerLogin uinfo
			,email=Github.detailedOwnerEmail uinfo
			,name=Github.detailedOwnerName uinfo
			,company=Github.detailedOwnerCompany uinfo
			,publicGists=Github.detailedOwnerPublicGists uinfo
			,followers=Github.detailedOwnerFollowers uinfo
			,following=Github.detailedOwnerFollowing uinfo
			,hireable=Github.detailedOwnerHireable uinfo
			,blog=Github.detailedOwnerBlog uinfo
			,publicRepos=Github.detailedOwnerPublicRepos uinfo
			,location=Github.detailedOwnerLocation uinfo
			,url=Github.detailedOwnerHtmlUrl uinfo
			,avatarUrl=Github.detailedOwnerAvatarUrl uinfo
			}

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
