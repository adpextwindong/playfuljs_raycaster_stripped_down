{-# LANGUAGE TemplateHaskell #-}
module Obelisk.State where

import Control.Lens
import Prelude hiding (map)
import Linear ( V2(..) )
import Foreign.C.Types

--In the style of https://github.com/jxv/diner/library/DinoRo-rush/blob/mastush/State.hs
data PVars = PVars {
                position :: V2 Double,
                direction :: V2 Double
             } deriving (Show)


data WallType = EW | FW | DW --Empty Wall, Full Wall, Door Wall
data WorldTiles = WorldTiles {
                    mapTiles :: [[WallType]],
                    worldSize :: CInt
                  }

rFW :: [WallType]
rFW = repeat FW
rEW :: [WallType]
rEW = repeat EW

godboltMap :: WorldTiles
godboltMap = WorldTiles map (fromIntegral $ length map)
    where map = [take 10 rFW,
              FW : take 3 rEW ++ [FW] ++ take 4 rEW ++ [FW],
              FW : take 3 rEW ++ [FW] ++ take 4 rEW ++ [FW],
              take 3 rFW ++ [DW] ++ [FW] ++ take 4 rEW ++ [FW],
              FW : take 3 rEW ++ [FW] ++ take 4 rEW ++ [FW],
              [FW,DW] ++ take 3 rFW ++ take 4 rEW ++ [FW],
              FW : take 3 rEW ++ take 4 rFW ++ [DW, FW],
              FW : take 8 rEW ++ [FW],
              FW : take 8 rEW ++ [FW],
              take 10 rFW]


data Vars = Vars {
                player :: PVars,
                world :: WorldTiles
            }

initPVars :: PVars
initPVars = PVars (V2 2.5 2.5) (V2 1.0 1.0)

initVars :: Vars
initVars = Vars initPVars godboltMap

makeClassy ''Vars
makeClassy ''PVars
makeClassy ''WorldTiles

instance HasPVars Vars where
    pVars = lens player (\v s -> v { player = s})

instance HasWorldTiles Vars where
    worldTiles = lens world (\v s -> v { world = s})