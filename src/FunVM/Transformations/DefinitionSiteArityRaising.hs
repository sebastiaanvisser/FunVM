module FunVM.Transformations.DefinitionSiteArityRaising
  ( transform
  ) where

import FunVM.Core
import qualified FunVM.Transformations.GenericTransform as GT

transform :: Module -> Module
transform = GT.transform applicable updateWorker updateWrapper

applicable :: ValBind -> Bool
applicable (Bind _ v) = any (moreThan 1) (f (Val v))
  where
    f :: Expr -> [[()]]
    f (Val (Lam _ e)) = let (bds:bdss) = f e
                        in (() : bds):bdss
    f (Let _ _ e)     = [] : f e
    f _               = [[]]
    moreThan :: Int -> [a] -> Bool
    moreThan _ []     = False
    moreThan 0 (_:_)  = True
    moreThan x (_:ys) = moreThan (x - 1) ys

updateWorker :: ValBind -> ValBind
updateWorker (Bind (TermPat x t@Fun{}) l@Lam{}) =
  let (pts, rts, ps, b) = f t (Val l)
  in Bind (TermPat x (Fun pts rts)) (Lam ps b)
  where
    f :: Type -> Expr -> ([Bind], [Type], [Bind], Expr)
    f (Fun pbs [rt]) (Val (Lam ps b)) = let (pbs', rts', ps', b') = f rt b
                                        in (pbs ++ pbs', rts', ps ++ ps', b')
    f t' (Let bs e1 e2) = let (pbs, rts, ps, b) = f t' e2
                          in ([], [pbs `Fun` rts], [], Let bs e1 (Val $ Lam ps b))
    f t' e = ([], [t'], [], e)
updateWorker vb = vb

updateWrapper :: ValBind -> ValBind -> ValBind
updateWrapper (Bind (TermPat _ t) _) (Bind p@(TermPat x _) (Lam ps' body)) = Bind p (Lam ps' (f body))
  where
    wNm  = x ++ "_worker"
    mwNm = Just $ wNm

    f :: Expr -> Expr
    f (Val (Lam ps b))    = Val (Lam ps (f b))
    f (Val (Delay e))     = Val (Delay (f e))
    f e@(App e1 _)
      | appVar e1 == mwNm = foldl (@@) (Var wNm) (jn (shape t) (args e))
                            
    f (App e1 e2)         = App (f e1) (f e2)
    f (Multi es)          = Multi (map f es)
    f (Force e)           = Force (f e)
    f (Let bs e1 e2)      = Let bs e1 (f e2)
    f (LetRec vbs e)      = LetRec vbs (f e)
    f e                   = e

    appVar :: Expr -> Maybe Id
    appVar (Val (Delay e))  = appVar e
    appVar (App (Var nm) _) = Just nm
    appVar (App e1       _) = appVar e1
    appVar (Force e)        = appVar e
    appVar (Let _ _ e2)     = appVar e2
    appVar (LetRec _ e)     = appVar e
    appVar _ = Nothing

    args :: Expr -> [Expr]
    args (App e1@App{} e2) = args e1 ++ args e2
    args (App _        e2) = args e2
    args (Multi es)        = es
    args e                 = [e]

    jn []     _  = []
    jn (n:ns) xs = let (ys, zs) = splitAt n xs
                   in ys : jn ns zs

updateWrapper _ vb = vb

shape :: Type -> [Int]
shape (Fun bs [t]) = length bs : shape t
shape (Fun bs ts)  = [length bs, length ts]
shape _            = []

