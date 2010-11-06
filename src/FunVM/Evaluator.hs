{-# LANGUAGE DoRec #-}
module FunVM.Evaluator
  ( Values
  , Value (..)
  , Env
  , eval
  ) where

import Control.Monad.Error
import Data.Function
import Data.List

import FunVM.Build
import FunVM.Destructors
import FunVM.Pretty ()
import FunVM.Syntax

-- | A value is multiple Vals
type Values = [Value]

data Value
  = ValBase   Literal
  | ValFun    Env [Bind] Expr
  | ValThunk  Env Expr
  | ValPrim   String
  deriving (Eq, Show)

type Env = [(Id, Value)]
type Eval a = Either String a

val :: Env -> Val -> Value
val _   (Lit   l)    = ValBase l
val env (Lam   ps e) = ValFun (closureEnv env e) ps e
val env (Delay e)    = ValThunk (closureEnv env e) e
val _   (Prim  s _)  = ValPrim s

eval :: Env -> Expr -> Eval Values
eval env (Val v)            = return [val env v]
eval env (Var x)            = maybe (throwError $ "Variable '" ++ x ++ "' not in environment.")
                                    (return . return)
                                    (lookup x env)
eval env (App e es)         = do
  f <- eval env e
  case f of
    [ValPrim s] -> do
      args <- eval env es
      ffi s args
    [ValFun env' ps body] -> do
      args <- eval env es
      let env'' = zip (map bindId ps) args `mergeEnvs` env'
      eval env'' body
    x -> throwError $ "Can't apply to non-function `" ++ show x ++ "'."
eval env (Let ps e1 e2)  = do
  vs <- eval env e1
  let env' = zip (map bindId ps) vs
  eval (env' `mergeEnvs` env) e2
eval env (LetRec bs e)     = do
  rec env' <- mapM (valBind (evalValBind (env' `mergeEnvs` env))) bs
  eval env' e
eval env (Multi es)         = concat `fmap` mapM (eval env) es
eval env (Force e)          = do
  v <- eval env e
  case v of
    [ValThunk env' e'] -> eval env' e'
    x -> throwError $ "Can't force non-thunk `" ++ show x ++ "'."

evalValBind :: Env -> Bind -> Val -> Eval (Id, Value)
evalValBind env b v = do
  let x = bindId b
  let v'= val env v
  return $ (x, v')

bindId :: Bind -> Id
bindId (TermPat x _) = x
bindId (TypePat x _) = x

closureEnv :: Env -> Expr -> Env
closureEnv env e = intersectBy ((==) `on` fst) env (map (\x -> (x, undefined)) (fv e))

mergeEnvs :: Env -> Env -> Env
mergeEnvs env1 env2 = nubBy ((==) `on` fst) (env1 ++ env2)

ffi :: String -> Values -> Eval Values
ffi "primAdd" [ValBase (Integer x _), ValBase (Integer y _)] = intVal (x + y)
ffi "primSub" [ValBase (Integer x _), ValBase (Integer y _)] = intVal (x - y)
ffi "primMul" [ValBase (Integer x _), ValBase (Integer y _)] = intVal (x * y)
ffi "primEq"  [ValBase (Integer x _), ValBase (Integer y _)] = intVal (if x == y then 1 else 0)
ffi "primOr"  [ValBase (Integer x _), ValBase (Integer y _)] = intVal (if x /= 0 || y /= 0 then 1 else 0)
ffi "primIf"  [ValBase (Integer p _), _, x, y]  = return $ if p == 0 then [y] else [x]
ffi s _  = throwError $ "Unknown Pim call `" ++ s ++ "'"

intVal :: Integer -> Eval Values
intVal x = return [ValBase $ Integer x int32]

