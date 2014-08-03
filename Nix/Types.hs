{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE OverloadedStrings #-}

module Nix.Types where

import           Control.Monad hiding (forM_, mapM, sequence)
import           Data.Data
import           Data.Foldable
import           Data.Map (Map)
import qualified Data.Map as Map
import           Data.Text hiding (concat, concatMap, head, map)
import           Data.Traversable
import           GHC.Generics
import           Prelude hiding (readFile, concat, concatMap, elem, mapM,
                                 sequence)

newtype Fix (f :: * -> *) = Fix { outF :: f (Fix f) }

cata :: Functor f => (f a -> a) -> Fix f -> a
cata f = f . fmap (cata f) . outF

cataM :: (Traversable f, Monad m) => (f a -> m a) -> Fix f -> m a
cataM f = f <=< mapM (cataM f) . outF

data NAtom
    = NStr Text
    | NInt Integer
    | NPath FilePath
    | NBool Bool
    | NSym Text
    | NNull
    deriving (Eq, Ord, Generic, Typeable, Data)

instance Show (NAtom) where
    show (NStr s)  = "NStr " ++ show s
    show (NInt i)  = "NInt " ++ show i
    show (NPath p) = "NPath " ++ show p
    show (NBool b) = "NBool " ++ show b
    show (NSym s)  = "NSym " ++ show s
    show NNull     = "NNull"

atomText :: NAtom -> Text
atomText (NStr s)  = s
atomText (NInt i)  = pack (show i)
atomText (NPath p) = pack p
atomText (NBool b) = if b then "true" else "false"
atomText (NSym s)  = s
atomText NNull     = "null"

data NOperF r
    = NNot r
    | NNeg r

    | NEq r r
    | NNEq r r
    | NLt r r
    | NLte r r
    | NGt r r
    | NGte r r
    | NAnd r r
    | NOr r r
    | NImpl r r
    | NUpdate r r
    | NHasAttr r r
    | NAttr r r

    | NPlus r r
    | NMinus r r
    | NMult r r
    | NDiv r r
    | NConcat r r
    deriving (Eq, Ord, Generic, Typeable, Data, Functor)

instance Show f => Show (NOperF f) where
    show (NNot r) = "! " ++ show r
    show (NNeg r) = "-"  ++ show r

    show (NEq r1 r2)      = show r1 ++ " == " ++ show r2
    show (NNEq r1 r2)     = show r1 ++ " != " ++ show r2
    show (NLt r1 r2)      = show r1 ++ " < " ++ show r2
    show (NLte r1 r2)     = show r1 ++ " <= " ++ show r2
    show (NGt r1 r2)      = show r1 ++ " > " ++ show r2
    show (NGte r1 r2)     = show r1 ++ " >= " ++ show r2
    show (NAnd r1 r2)     = show r1 ++ " && " ++ show r2
    show (NOr r1 r2)      = show r1 ++ " || " ++ show r2
    show (NImpl r1 r2)    = show r1 ++ " -> " ++ show r2
    show (NUpdate r1 r2)  = show r1 ++ " // " ++ show r2
    show (NHasAttr r1 r2) = show r1 ++ " ? " ++ show r2
    show (NAttr r1 r2)    = show r1 ++ "." ++ show r2

    show (NPlus r1 r2)    = show r1 ++ " + " ++ show r2
    show (NMinus r1 r2)   = show r1 ++ " - " ++ show r2
    show (NMult r1 r2)    = show r1 ++ " * " ++ show r2
    show (NDiv r1 r2)     = show r1 ++ " / " ++ show r2

    show (NConcat r1 r2)  = show r1 ++ " ++ " ++ show r2

data NSetBind = Rec | NonRec
    deriving (Ord, Eq, Generic, Typeable, Data)

instance Show NSetBind where
    show Rec = "rec"
    show NonRec = ""

-- | A single line of the bindings section of a let expression.
data Binding r = NamedVar r r | Inherit [r] | ScopedInherit r [r]
     deriving (Typeable, Data, Ord, Eq, Functor)

instance Show r => Show (Binding r) where
         show (NamedVar name val) = show name ++ " = " ++ show val ++ ";"
         show (Inherit names) = "inherit " ++ concatMap show names ++ ";"
         show (ScopedInherit context names) = "inherit (" ++ show context ++ ") " ++ concatMap show names ++ ";"

data FormalParamSet r = FormalParamSet (Map Text (Maybe r))
                 deriving (Eq, Ord, Generic, Typeable, Data, Functor)

instance Show r => Show (FormalParamSet r) where
    show (FormalParamSet h) = "{ " ++ go (Map.toList h) ++ " }"
      where
        go [] = ""
        go [x] = showArg x
        go (x:xs) = showArg x ++ ", " ++ go xs

        showArg (k, Nothing) = unpack k
        showArg (k, Just v) = unpack k ++ " ? " ++ show v

-- | @Formals@ represents all the ways the formal parameters to a
-- function can be represented.
data Formals r =
   FormalName Text |
   FormalSet (FormalParamSet r) |
   FormalLeftAt Text (FormalParamSet r) |
   FormalRightAt (FormalParamSet r)  Text
   deriving (Ord, Eq, Generic, Typeable, Data, Functor)

instance Show r => Show (Formals r) where
    show (FormalName n) = show n
    show (FormalSet s) = show s
    show (FormalLeftAt n s) = show n ++ "@" ++ show s
    show (FormalRightAt s n) = show s ++ "@" ++ show n

-- | @formalsAsMap@ combines the outer and inner name bindings of
-- 'Formals'
formalsAsMap :: Formals r -> Map Text (Maybe r)
formalsAsMap (FormalName n) = Map.singleton n Nothing
formalsAsMap (FormalSet (FormalParamSet s)) = s
formalsAsMap (FormalLeftAt n (FormalParamSet s)) = Map.insert n Nothing s
formalsAsMap (FormalRightAt (FormalParamSet s) n) = Map.insert n Nothing s

data NExprF r
    = NConstant NAtom

    | NOper (NOperF r)

    | NList [r]
      -- ^ A "concat" is a list of things which must combine to form a string.
    | NArgs (Formals r)
    | NSet NSetBind [Binding r]

    | NLet [Binding r] r
    | NIf r r r
    | NWith r r
    | NAssert r r

    | NVar r
    | NApp r r
    | NAbs r r
      -- ^ The untyped lambda calculus core
    deriving (Ord, Eq, Generic, Typeable, Data, Functor)

type NExpr = Fix NExprF

instance Show (Fix NExprF) where show (Fix f) = show f
instance Eq (Fix NExprF)   where Fix x == Fix y = x == y
instance Ord (Fix NExprF)  where compare (Fix x) (Fix y) = compare x y

instance Show f => Show (NExprF f) where
    show (NConstant x) = show x
    show (NOper x) = show x

    show (NList l) = "[ " ++ go l ++ " ]"
      where
        go [] = ""
        go [x] = show x
        go (x:xs) = show x ++ ", " ++ go xs

    show (NArgs fs) = show fs
    show (NSet b xs) = show b ++ " { " ++ concatMap show xs ++ " }"

    show (NLet v e)    = "let " ++ show v ++ "; " ++ show e
    show (NIf i t e)   = "if " ++ show i ++ " then " ++ show t ++ " else " ++ show e
    show (NWith c v)   = "with " ++ show c ++ "; " ++ show v
    show (NAssert e v) = "assert " ++ show e ++ "; " ++ show v

    show (NVar v)      = show v
    show (NApp f x)    = show f ++ " " ++ show x
    show (NAbs a b)    = show a ++ ": " ++ show b

dumpExpr :: NExpr -> String
dumpExpr = cata phi where
  phi (NConstant x) = "NConstant " ++ show x
  phi (NOper x)     = "NOper " ++ show x
  phi (NList l)     = "NList [" ++ show l ++ "]"
  phi (NArgs xs)  = "NArgs " ++ show xs
  phi (NSet b xs)   = "NSet " ++ show b ++ " " ++ show xs
  phi (NLet v e)    = "NLet " ++ show v ++ " " ++ e
  phi (NIf i t e)   = "NIf " ++ i ++ " " ++ t ++ " " ++ e
  phi (NWith c v)   = "NWith " ++ c ++ " " ++ v
  phi (NAssert e v) = "NAssert " ++ e ++ " " ++ v
  phi (NVar v)      = "NVar " ++ v
  phi (NApp f x)    = "NApp " ++ f ++ " " ++ x
  phi (NAbs a b)    = "NAbs " ++ a ++ " " ++ b

mkInt :: Integer -> NExpr
mkInt = Fix . NConstant . NInt

mkStr :: Text -> NExpr
mkStr = Fix . NConstant . NStr

mkPath :: FilePath -> NExpr
mkPath = Fix . NConstant . NPath

mkSym :: Text -> NExpr
mkSym = Fix . NConstant . NSym

mkBool :: Bool -> NExpr
mkBool = Fix . NConstant . NBool

mkNull :: NExpr
mkNull = Fix (NConstant NNull)

-- An 'NValue' is the most reduced form of an 'NExpr' after evaluation
-- is completed.
data NValueF r
    = NVConstant NAtom
    | NVList [r]
    | NVSet (Map Text r)
    | NVArgSet (Map Text (Maybe r))
    | NVFunction r (NValue -> IO r)
    deriving (Generic, Typeable)

type NValue = Fix NValueF

instance Show (Fix NValueF) where show (Fix f) = show f

instance Functor NValueF where
    fmap _ (NVConstant a) = NVConstant a
    fmap f (NVList xs) = NVList (fmap f xs)
    fmap f (NVSet h) = NVSet (fmap f h)
    fmap f (NVArgSet h) = NVArgSet (fmap (fmap f) h)
    fmap f (NVFunction argset k) = NVFunction (f argset) (fmap f . k)

instance Show f => Show (NValueF f) where
    show (NVConstant a)        = "NVConstant " ++ show a
    show (NVList xs)           = "NVList " ++ show xs
    show (NVSet h)             = "NVSet " ++ show h
    show (NVArgSet h)          = "NVArgSet " ++ show h
    show (NVFunction argset _) = "NVFunction " ++ show argset

valueText :: NValue -> Text
valueText = cata phi where
    phi (NVConstant a)   = atomText a
    phi (NVList _)       = error "Cannot coerce a list to a string"
    phi (NVSet _)        = error "Cannot coerce a set to a string"
    phi (NVArgSet _)     = error "Cannot coerce an argument list to a string"
    phi (NVFunction _ _) = error "Cannot coerce a function to a string"
