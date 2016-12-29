{-
Copyright 2016 SlamData, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}

module Matryoshka.Fold where

import Prelude

import Control.Comonad (class Comonad, duplicate, extract)
import Control.Comonad.Cofree (Cofree, mkCofree)
import Control.Comonad.Env.Trans (EnvT)

import Data.Foldable (class Foldable, foldMap)
import Data.List (List)
import Data.Monoid.Disj (Disj(..))
import Data.Newtype (alaF)
import Data.Profunctor.Strong ((&&&))
import Data.Traversable (class Traversable, traverse)
import Data.Tuple (Tuple(..))

import Matryoshka.Algebra (Algebra, AlgebraM, ElgotAlgebra, GAlgebra, GAlgebraM)
import Matryoshka.Class.Corecursive (class Corecursive, embed)
import Matryoshka.Class.Recursive (class Recursive, project)
import Matryoshka.DistributiveLaw (DistributiveLaw, distGHisto, distHisto, distZygo, distZygoT)
import Matryoshka.Util (mapR, traverseR)
import Matryoshka.Transform (AlgebraicGTransform, Transform, TransformM)

cata ∷ ∀ f t a. Recursive t f ⇒ Algebra f a → t → a
cata f = go
  where
  go t = f $ map go $ project t

cataM
  ∷ ∀ f t m a
  . (Recursive t f, Monad m, Traversable f)
  ⇒ AlgebraM m f a
  → t
  → m a
cataM f = go
  where
  go t = f =<< traverse go (project t)

gcata
  ∷ ∀ f t w a
  . (Recursive t f, Comonad w)
  ⇒ DistributiveLaw f w
  → GAlgebra w f a
  → t
  → a
gcata k g = g <<< extract <<< go
  where
  go t = k $ map (duplicate <<< map g <<< go) (project t)

gcataM
  ∷ ∀ f t m w a
  . (Recursive t f, Monad m, Comonad w, Traversable f, Traversable w)
  ⇒ DistributiveLaw f w
  → GAlgebraM w m f a
  → t
  → m a
gcataM k g = g <<< extract <=< loop
  where
  loop t = k <$> traverse (map duplicate <<< traverse g <=< loop) (project t)

elgotCata
  ∷ ∀ f t w a
  . (Recursive t f, Comonad w)
  ⇒ DistributiveLaw f w
  → ElgotAlgebra w f a
  → t
  → a
elgotCata k g = g <<< go
  where
  go t = k $ map (map g <<< duplicate <<< go) (project t)

transCata
  ∷ ∀ f t g u
  . (Recursive t f, Corecursive u g)
  ⇒ Transform u f g
  → t
  → u
transCata f = go
  where
  go t = mapR (f <<< map go) t

transCataT
  ∷ ∀ f t
  . (Recursive t f, Corecursive t f)
  ⇒ (t → t)
  → t
  → t
transCataT f = go
  where
  go t = f $ mapR (map go) t

transCataM
  ∷ ∀ f t g u m
  . (Recursive t f, Corecursive u g, Monad m, Traversable f)
  ⇒ TransformM m u f g
  → t
  → m u
transCataM f = go
  where
  go t = traverseR (f <=< traverse go) t

transCataTM
  ∷ ∀ f t m
  . (Recursive t f, Corecursive t f, Monad m, Traversable f)
  ⇒ (t → m t)
  → t
  → m t
transCataTM f = go
  where
  go t = f =<< traverseR (traverse go) t

topDownCata
  ∷ ∀ t f a
  . (Recursive t f, Corecursive t f)
  ⇒ (a → t → Tuple a t)
  → a
  → t
  → t
topDownCata f = go
  where
  go a t = case f a t of
    Tuple a' tf → mapR (map (go a')) tf

topDownCataM
  ∷ ∀ t f m a
  . (Recursive t f, Corecursive t f, Monad m, Traversable f)
  ⇒ (a → t → m (Tuple a t))
  → a
  → t
  → m t
topDownCataM f = go
  where
  go a t = f a t >>= case _ of
    Tuple a' tf → traverseR (traverse (go a')) tf

prepro
  ∷ ∀ f t a
  . (Recursive t f, Corecursive t f)
  ⇒ (f ~> f)
  → Algebra f a
  → t
  → a
prepro f g = go
  where
  go t = g $ (go <<< cata (embed <<< f)) <$> project t

gprepro
  ∷ ∀ f t w a
  . (Recursive t f, Corecursive t f, Comonad w)
  ⇒ DistributiveLaw f w
  → (f ~> f)
  → GAlgebra w f a
  → t
  → a
gprepro f g h = extract <<< go
  where
  go t = h <$> f (duplicate <<< go <<< cata (embed <<< g) <$> project t)

transPrepro
  ∷ forall f t g u
  . (Recursive t f, Corecursive t f, Corecursive u g)
  ⇒ (f ~> f)
  → Transform u f g
  → t
  → u
transPrepro f g = go
  where
  go t = mapR (g <<< map (go <<< transCata f)) t

para ∷ ∀ f t a. Recursive t f ⇒ GAlgebra (Tuple t) f a → t → a
para f = go
  where
  go ∷ t → a
  go t = f (g <$> project t)
  g ∷ t → Tuple t a
  g t = Tuple t (go t)

paraM
  ∷ ∀ f t m a
  . (Recursive t f, Monad m, Traversable f)
  ⇒ GAlgebraM (Tuple t) m f a
  → t
  → m a
paraM f = go
  where
  go t = f =<< traverse (map (Tuple t) <<< go) (project t)

gpara
  ∷ ∀ f t w a
  . (Recursive t f, Corecursive t f, Comonad w)
  ⇒ DistributiveLaw f w
  → GAlgebra (EnvT t w) f a
  → t
  → a
gpara = gzygo embed

elgotPara ∷ ∀ f t a. Recursive t f ⇒ ElgotAlgebra (Tuple t) f a → t → a
elgotPara f = go
  where
  go t = f (Tuple t (go <$> project t))

transPara
  ∷ forall f t g u
  . (Recursive t f, Corecursive u g)
  ⇒ AlgebraicGTransform (Tuple t) u f g
  → t
  → u
transPara f = go
  where
  go t = mapR (f <<< map (id &&& go)) t

transParaT
  ∷ ∀ f t
  . (Recursive t f, Corecursive t f)
  ⇒ (t → t → t)
  → t
  → t
transParaT f = go
  where
  go t = f t (mapR (map go) t)

zygo
  ∷ ∀ f t a b
  . Recursive t f
  ⇒ Algebra f b
  → GAlgebra (Tuple b) f a
  → t
  → a
zygo = gcata <<< distZygo

gzygo
  ∷ ∀ f t w a b
  . (Recursive t f, Comonad w)
  ⇒ Algebra f b
  → DistributiveLaw f w
  → GAlgebra (EnvT b w) f a
  → t
  → a
gzygo f w = gcata (distZygoT f w)

elgotZygo
  ∷ ∀ f t a b
  . Recursive t f
  ⇒ Algebra f b
  → ElgotAlgebra (Tuple b) f a
  → t
  → a
elgotZygo = elgotCata <<< distZygo

gElgotZygo
  ∷ ∀ f t w a b
  . (Recursive t f, Comonad w)
  ⇒ Algebra f b
  → DistributiveLaw f w
  → ElgotAlgebra (EnvT b w) f a
  → t
  → a
gElgotZygo f w = elgotCata (distZygoT f w)

mutu
  ∷ ∀ f t a b
  . Recursive t f
  ⇒ GAlgebra (Tuple a) f b
  → GAlgebra (Tuple b) f a
  → t
  → a
mutu f g = g <<< map go <<< project
  where
  go x = Tuple (mutu g f x) (mutu f g x)

histo
  ∷ ∀ f t a
  . Recursive t f
  ⇒ GAlgebra (Cofree f) f a
  → t
  → a
histo = gcata distHisto

ghisto
  ∷ ∀ f t h a
  . (Recursive t f, Functor h)
  ⇒ DistributiveLaw f h
  → GAlgebra (Cofree h) f a
  → t
  → a
ghisto g = gcata (distGHisto g)

elgotHisto
  ∷ ∀ f t a
  . Recursive t f
  ⇒ ElgotAlgebra (Cofree f) f a
  → t
  → a
elgotHisto = elgotCata distHisto

annotateTopDown
  ∷ ∀ t f a
  . Recursive t f
  ⇒ (a → f t → a)
  → a
  → t
  → Cofree f a
annotateTopDown f z = go
  where
  go t =
    let ft = project t
    in mkCofree (f z ft) (map go ft)

annotateTopDownM
  ∷ ∀ t f m a
  . (Recursive t f, Monad m, Traversable f)
  ⇒ (a → f t → m a)
  → a
  → t
  → m (Cofree f a)
annotateTopDownM f z = go
  where
  go t =
    let ft = project t
    in (\h -> mkCofree h <$> traverse go ft) =<< f z ft

isLeaf ∷ ∀ f t. (Recursive t f, Foldable f) ⇒ t → Boolean
isLeaf t = alaF Disj foldMap (const true) (project t)

children ∷ ∀ f t. (Recursive t f, Foldable f) ⇒ t → List t
children = foldMap pure <<< project

universe ∷ ∀ f t. (Recursive t f, Foldable f) ⇒ t → List t
universe t = universe =<< children t

lambek ∷ ∀ f t. (Recursive t f, Corecursive t f) ⇒ t → f t
lambek = cata (map embed)
