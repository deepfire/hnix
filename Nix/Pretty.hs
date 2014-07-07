module Nix.Pretty where

import Text.PrettyPrint.HughesPJ
import Nix.Types
import Data.Map (toList)
import Data.Text (Text, unpack)

prettyBind :: (NExpr, NExpr) -> Doc
prettyBind (n, v) = prettyNix n <+> equals <+> prettyNix v <> semi

prettySetArg :: (Text, Maybe NExpr) -> Doc
prettySetArg (n, Nothing) = text (unpack n)
prettySetArg (n, Just v) = text (unpack n) <+> text "?" <+> prettyNix v

infixOper :: NExpr -> String -> NExpr -> Doc
infixOper l op r = prettyNix l <+> text op <+> prettyNix r

prettyOper :: NOperF NExpr -> Doc
prettyOper (NNot r) = text "!" <> prettyNix r
prettyOper (NNeg r) = text "-" <> prettyNix r
prettyOper (NEq r1 r2)      = infixOper r1 "==" r2
prettyOper (NNEq r1 r2)     = infixOper r1 "!=" r2
prettyOper (NLt r1 r2)      = infixOper r1 "<" r2
prettyOper (NLte r1 r2)     = infixOper r1 "<=" r2
prettyOper (NGt r1 r2)      = infixOper r1 ">" r2
prettyOper (NGte r1 r2)     = infixOper r1 ">=" r2
prettyOper (NAnd r1 r2)     = infixOper r1 "&&" r2
prettyOper (NOr r1 r2)      = infixOper r1 "||" r2
prettyOper (NImpl r1 r2)    = infixOper r1 ">" r2
prettyOper (NUpdate r1 r2)  = infixOper r1 "//" r2
prettyOper (NHasAttr r1 r2) = infixOper r1 "?" r2
prettyOper (NAttr r1 r2)    = prettyNix r1 <> text "." <> prettyNix r2

prettyOper (NPlus r1 r2)    = infixOper r1 "+" r2
prettyOper (NMinus r1 r2)   = infixOper r1 "-" r2
prettyOper (NMult r1 r2)    = infixOper r1 "*" r2
prettyOper (NDiv r1 r2)     = infixOper r1 "/" r2

prettyOper (NConcat r1 r2)  = infixOper r1 "++" r2

prettyAtom :: NAtom -> Doc
prettyAtom (NStr s) = doubleQuotes $ text $ unpack $ s
prettyAtom atom = text $ unpack $ atomText atom

prettyNix :: NExpr -> Doc
prettyNix (Fix expr) = go expr where
  go (NConstant atom) = prettyAtom atom
  go (NOper oper) = prettyOper oper 
  go (NList list) = lbrack <+> (fsep $ map prettyNix list) <+> rbrack

  go (NArgSet args) = lbrace <+> (vcat $ map prettySetArg $ toList args) <+> rbrace

  go (NSet rec list) = 
    (case rec of Rec -> "rec"; NonRec -> empty)
    <+> lbrace <+> (vcat $ map prettyBind list) <+> rbrace

  go (NLet binds body) = text "let"
  go (NIf cond trueBody falseBody) =
    (text "if" <+> prettyNix cond)
    $$ (text "then" <+> prettyNix trueBody)
    $$ (text "else" <+> prettyNix falseBody)

  go (NWith scope body) = text "with" <+> prettyNix scope <> semi <+> prettyNix body
  go (NAssert cond body) = text "assert" <+> prettyNix cond <> semi <+> prettyNix body
  go (NInherit attrs) = text "inherit"

  go (NVar e) = prettyNix e
  go (NApp fun arg) = prettyNix fun <+> prettyNix arg
  go (NAbs args body) = (prettyNix args <> colon) $$ prettyNix body
