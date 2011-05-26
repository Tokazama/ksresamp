## Some useful auxiliary functions

## grids: a LIST of monotonically increasing coordinate grids.  For
## example, grids <- list(grid.x=seq(0, 100, 2), grid.y=exp(seq(1, 5,
## .2))).

artifacts <- function(grids, center=rep(0, length(grids)), std=0.3,
                   radius=1.0, magnitude=1.0, xscale=diag(length(grids))) {
  Ns <- sapply(grids, length)
  ## First, determine a rough rectangle which contains all the
  ## artifacts.
  lambda1 <- max(abs(eigen(xscale, only.values=TRUE)$values))
  L1 <- lambda1 *radius
  grids2 <- NULL; inds <- NULL
  for (n in 1:length(Ns)){
    grids2[[n]] <- grids[[n]] - center[n]
    inds[[n]] <- seq(Ns[n])[grids2[[n]] >= -L1 & grids2[[n]] <=L1]
    grids2[[n]] <- grids2[[n]][inds[[n]]]
  }
  ## Now compute the artifacts according to a Gaussian function
  coords <- solve(xscale) %*% t(expand.grid(grids2))
  func1 <- function(xvec) ifelse(sum(xvec**2) > radius**2, 0, prod(dnorm(xvec, sd=std)))
  art1 <- magnitude * array(apply(coords, 2, func1), sapply(inds, length))
  ## return the array
  W <- array(0, Ns)
  ## use a computing trick to subset/assign value to an arbitrary dim array
  cmd <- paste("W", "[",paste(inds,collapse=","),"]", "<-","art1", sep="")
  eval(parse(text=cmd))
  return(W)
}

## compute the L1, L2, L-inf norm (over number of observations) of a
## fitted object.  Assuming EQUAL grid.
norms <- function(Y, norm=c("L1", "L2", "Linf")){
  rr <- NULL
  for (nn in norm){
    rr[[nn]] <- switch(nn, "L1"=mean(abs(Y)),
                       "L2"=sqrt(mean(Y^2)),
                       "Linf"=max(abs(Y)),
                       stop("Norms implemented: L1, L2, and Linf."))
  }
  return(rr)
}

## An R implementation of multivariate N-stat, 30 times faster than
## ksmooth, so a) I don't have to re-write it in C; b) I can afford to
## compute all 3 kernels (the default option of function norms()).
Ndist <- function(Xlist, Ylist, kernels=c("L1", "L2", "Linf")){
  ## Xlist, Ylist are lists of arrays/vectors.  Default Kernels is set
  ## to Linf. BG: between group dists; WGX, WGY are within group
  ## dists.
  Nx <- length(Xlist); Ny <- length(Ylist); N <- Nx + Ny
  XYlist <- c(Xlist,Ylist)
  dist.pairs <- array(0, c(length(kernels),N,N), dimnames=list(kernels,1:N,1:N))
  for (i in 2:N){
    for (j in 1:(i-1)){
      d.ij <- norms(XYlist[[i]] - XYlist[[j]])
        dist.pairs[,i,j] <- d.ij; dist.pairs[,j,i] <- d.ij
    }}
  X.ind <- 1:Nx; Y.ind <- (Nx+1):N
  BG <- 2*apply(dist.pairs[, X.ind, Y.ind], 1, mean)
  WGX <- apply(dist.pairs[, X.ind, X.ind], 1, mean) #symmetry
  WGY <- apply(dist.pairs[, Y.ind, Y.ind], 1, mean)
  return(sqrt(BG-WGX-WGY))
}

## This is the permutation version of Ndist.  It employes a trick to
## GREATLY reduce the computing time: it first computes all pairwise
## distances, then use permutation of these NUMBERS to compute the
## permuted N-stats.  For flexibility combs is an external list of
## permutations/combinations which can be generated by either
## combn(N,Nx,function(x) c(x, setdiff(1:N, x)), simplify=FALSE) or
## foreach(icount(rand.comb)) %do% sample(N).  See rep.test()
## for more details.

Ndist.perm <- function(Xlist, Ylist, combs, kernels=c("L1", "L2", "Linf")){
  Nx <- length(Xlist); Ny <- length(Ylist); N <- Nx + Ny
  XYlist <- c(Xlist,Ylist)
  dist.pairs <- array(0, c(length(kernels),N,N), dimnames=list(kernels,1:N,1:N))
  for (i in 2:N){
    for (j in 1:(i-1)){
      d.ij <- norms(XYlist[[i]] - XYlist[[j]])
        dist.pairs[,i,j] <- d.ij; dist.pairs[,j,i] <- d.ij
    }}
  my.Ns <- matrix(0, nrow=length(combs), ncol=length(kernels))
  colnames(my.Ns) <- kernels  
  for (k in 1:length(combs)){
    X.ind <- combs[[k]][1:Nx]; Y.ind <- combs[[k]][(Nx+1):N]
    BG <- 2*apply(dist.pairs[, X.ind, Y.ind], 1, mean)
    WGX <- apply(dist.pairs[, X.ind, X.ind], 1, mean) #symmetry
    WGY <- apply(dist.pairs[, Y.ind, Y.ind], 1, mean)
    my.Ns[k,] <- sqrt(BG-WGX-WGY)
  }
  return(my.Ns)
}

## flip: sort of wild bootstrap for an array.  Group action: G \cong 2^N.
flip <- function(diff.array){
  Y <- as.array(diff.array)
  g <- 2*array(rbinom(length(Y), 1, .5), dim(Y))-1
  return(g*Y)
}

## XYlist: a list of n arrays which are i.i.d. random vectors of length
## N under H0.  Permutation group action: G \cong n^N.
spatial.perm <- function(XYlist){
  n <- length(XYlist); Ns <- dim(XYlist[[1]])
  Amat <- matrix(unlist(XYlist), nrow=prod(Ns))
  Bmat <- t(apply(Amat, 1, sample))
  foreach(col=iter(Bmat)) %do% array(col, Ns)
}

## genboot.test().  Can be used in p-value evaluation when the number
## of permutations is small (<500). The generalized bootstrap is a
## smoothed bootstrap method (Chernick 1992 book, 6.2.2.).

## The default smoothing method is based on the generalized (Tukey)
## lambda distribution (Dudewicz, 1992).  Parameter estimation and
## probability computing is Implemented by R package "gld".

## Alternative methods include Gaussian (which is called "parametric
## bootstrap" by Efron and skew-normal distribution (3 parameter
## generalization of normal), implemented by R package "sn"; and may
## in the future include others.

## Efforts are made so to let this function deal gracefully with
## identical null vector case.  nullvec: typically a vector of summary
## statistics (like norms) generated by resampling under H0; x:
## typically the summary statistic computed from the original (could
## be H1) data.  Statistical validity: this summary statistic follows
## an asymptotic normal distribution under H0.

## The default alternative is "greater" because usually norm>0 and we
## want to show that x > nullvec.
.genboot.test.identical <- function(nullvec, x, alternative="greater"){
  ERR <- 10^-9
  x0a <- min(nullvec)-ERR; x0b <- max(nullvec)+ERR
  if (x > x0b){
    intv <- "high"
  } else if (x < x0a){
    intv <- "low"
  } else {
    intv <- "med"
  }
  pp <- switch(alternative,
               "greater"=switch(intv, high=0.0, med=0.5, low=1.0),
               "less"=switch(intv, high=1.0, med=0.5, low=0.0),
               "two.sided"=switch(intv, high=0.0, med=0.5, low=0.0),
               stop("Valid alternatives: greater, less, two.sided."))
  return(pp)
}

.genboot.test.gld <- function(nullvec, x, alternative="greater", ...){
  ## I choose this initgrid because it is way faster than the default.
  params <- starship(nullvec, initgrid=list(lcvect=(-2:2)/10, ldvect=(-2:2)/10), ...)$lambda
  prob <- do.call("pgl", c(list(x), params))
  pp <- switch(alternative,
               "greater"= 1-prob,
               "less"=prob,
               "two.sided"=2*(1-prob),
               stop("Valid alternatives: greater, less, two.sided."))
  return(pp)
}

.genboot.test.normal <- function(nullvec, x, alternative="greater"){
  params <- list("mean"=mean(nullvec), "sd"=sd(nullvec))
  prob <- do.call("pnorm", c(list(x), params))
  pp <- switch(alternative,
               "greater"= 1-prob,
               "less"=prob,
               "two.sided"=2*(1-prob),
               stop("Valid alternatives: greater, less, two.sided."))
  return(pp)
}

.genboot.test.sn <- function(nullvec, x, alternative="greater", ...){
  ## depends on package "sn"
  params <- sn.em(y=nullvec, ...)$dp
  prob <- do.call("psn", c(list(x), params))
  pp <- switch(alternative,
               "greater"= 1-prob,
               "less"=prob,
               "two.sided"=2*(1-prob),
               stop("Valid alternatives: greater, less, two.sided."))
  return(pp)
}

.genboot.test.null <- function(nullvec, x, alternative="greater"){
  ## A convenient function wrapper for nonparametric bootstrap test.
  prob <- sapply(x, function(xi) sum(xi>nullvec))/length(nullvec)
  pp <- switch(alternative,
               "greater"= 1-prob,
               "less"=prob,
               "two.sided"=2*(1-prob),
               stop("Valid alternatives: greater, less, two.sided."))
  return(pp)
}

genboot.test <- function(nullvec, x, alternative="greater", method="normal", ...){
  ERR <- 10^-9
  if (max(nullvec) - min(nullvec) < ERR) {
    pp <- .genboot.test.identical(nullvec, x, alternative)
  } else {                              #None identical vector case
    pp <- switch(method, 
                 "null"=.genboot.test.null(nullvec, x, alternative),
                 "normal"=.genboot.test.normal(nullvec, x, alternative),
                 "sn"=.genboot.test.sn(nullvec, x, alternative, ...),
                 "gld"=.genboot.test.gld(nullvec, x, alternative, ...),
                 stop("Valid methods: gld (genral lambda distribution), sn (skew-normal), normal, and null (the usual nonparametric estimate)."))
  }
  return(pp)
}

## Computes the reverse rank of x in x.perm.  This function can be
## used to compute permutation p-values quickly.  x can be a vector.

rev.rank <- function(x, x.perm) {
  y <- sort(x.perm, decreasing=TRUE)
  o <- order(x, decreasing=TRUE); ro <- order(o)
  rv <- rep(-1,length(x))
  z <- .C("vec_rev_rank", as.double(x[o]), as.double(y), 
          as.integer(length(x)), as.integer(length(y)),
          rv=as.integer(rv), PACKAGE = "ksresamp")
  return(z$rv[ro])
}
