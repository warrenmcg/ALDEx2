#  invocation:
#  use selex dataset from ALDEx2 library
#  x <- aldex.clr( reads, conditions, mc.samples=128, denom="all", verbose=FALSE, useMC=FALSE )
#  this function generates the centre log-ratio transform of Monte-Carlo instances
#  drawn from the Dirichlet distribution.

aldex.clr.function <- function( reads, conds, mc.samples=128, denom="all", verbose=FALSE, useMC=FALSE, summarizedExperiment=NULL ) {

# INPUT
# The 'reads' data.frame MUST have row
# and column names that are unique, and
# looks like the following:
#
#              T1a T1b  T2  T3  N1  N2
#   Gene_00001   0   0   2   0   0   1
#   Gene_00002  20   8  12   5  19  26
#   Gene_00003   3   0   2   0   0   0
#       ... many more rows ...
#
# ---------------------------------------------------------------------

# OUTPUT
# The output returned is a list (x) that contains Monte-Carlo instances of
# the centre log-ratio transformed values for each sample
# Access to values
# sample IDs: names(x)
# number of features (genes, OTUs): length(x[[1]][,1])
# number of Monte-Carlo Dirichlet instances: length(x[[1]][1,])
# feature names: rownames(x[[1]])

# coerce SummarizedExperiment reads into data.frame
if (summarizedExperiment) {
    reads <- data.frame(as.list(assays(reads,withDimnames=TRUE)))
    if (verbose) {
        print("converted SummarizedExperiment read count object into data frame")
    }
}

    # Fully validate and coerce the data into required formats
    # make sure that the multicore package is in scope and return if available
    has.BiocParallel <- FALSE
    if ("BiocParallel" %in% rownames(installed.packages()) & useMC){
        print("multicore environment is is OK -- using the BiocParallel package")
        #require(BiocParallel)
        has.BiocParallel <- TRUE
    }
    else {
        print("operating in serial mode")
    }

    # make sure that mc.samples is an integer, despite it being a numeric type value
    as.numeric(as.integer(mc.samples))

    #  remove all rows with reads less than the minimum set by minsum
    minsum <- 0

    # remove any row in which the sum of the row is 0
    z <- as.numeric(apply(reads, 1, sum))
    reads <- as.data.frame( reads[(which(z > minsum)),]  )

    if (verbose) print("removed rows with sums equal to zero")


    #  SANITY CHECKS ON THE DATA INPUT
    if ( any( round(reads) != reads ) ) stop("not all reads are integers")
    if ( any( reads < 0 ) )             stop("one or more reads are negative")

    for ( col in names(reads) ) {
        if ( any( ! is.finite( reads[[col]] ) ) )  stop("one or more reads are not finite")
    }

    if ( length(rownames(reads)) == 0 ) stop("rownames(reads) cannot be empty")
    if ( length(colnames(reads)) == 0 ) stop("colnames(reads) cannot be empty")

    if ( length(rownames(reads)) != length(unique(rownames(reads))) ) stop ("row names are not unique")
    if ( length(colnames(reads)) != length(unique(colnames(reads))) ) stop ("col names are not unique")
    if ( mc.samples < 128 ) warning("values are unreliable when estimated with so few MC smps")

    # add a prior expection to all remaining reads that are 0
    # this should be by a Count Zero Multiplicative approach, but in practice
    # this is not necessary because of the large number of features
    prior <- 0.5

    # This extracts the set of features to be used in the geometric mean computation
    feature.subset <- aldex.set.mode(reads, conds, denom)


    reads <- reads + prior

if (verbose == TRUE) print("data format is OK")

    # ---------------------------------------------------------------------
    # Generate a Monte Carlo instance of the frequencies of each sample via the Dirichlet distribution,
    # returns frequencies for each feature in each sample that are consistent with the
    # feature count observed as a proportion of the total counts per sample given
    # technical variation (i.e. proportions consistent with error observed when resequencing the same library)

    nr <- nrow( reads )
    rn <- rownames( reads )

    #this returns a list of proportions that are consistent with the number of reads per feature and the
    #total number of reads per sample

    # environment test, runs in multicore if possible
    if (has.BiocParallel){
        p <- bplapply( reads ,
            function(col) {
                q <- t( rdirichlet( mc.samples, col ) ) ;
                rownames(q) <- rn ;
                q })
        names(p) <- names(reads)
    }
    else{
        p <- lapply( reads ,
            function(col) {
                q <- t( rdirichlet( mc.samples, col ) ) ;
                rownames(q) <- rn ; q } )
    }

    # sanity check on the data, should never fail
    for ( i in 1:length(p) ) {
            if ( any( ! is.finite( p[[i]] ) ) ) stop("non-finite frequencies estimated")
    }

if (verbose == TRUE) print("dirichlet samples complete")

    # ---------------------------------------------------------------------
    # Take the log2 of the frequency and subtract the geometric mean log2 frequency per sample
    # i.e., do a centered logratio transformation as per Aitchison

    # apply the function over elements in a list, that contains an array

    # DEFAULT
    if(length(feature.subset) == nr)
    {
        # Default ALDEx2
        if (has.BiocParallel){
            l2p <- bplapply( p, function(m) {
                apply( log2(m), 2, function(col) { col - mean(col) } )
            })
            names(l2p) <- names(p)
        }
        else{
            l2p <- lapply( p, function(m) {
                apply( log2(m), 2, function(col) { col - mean(col) } )
            })
        }
    } else {
        ## IQLR or ZERO
        feat.result <- vector("list", length(unique(conds))) # Feature Gmeans
        condition.list <- vector("list", length(unique(conds)))    # list to store conditions

        for (i in 1:length(unique(conds)))
        {
            condition.list[[i]] <- which(conds == unique(conds)[i]) # Condition list
            feat.result[[i]] <- lapply( p[condition.list[[i]]], function(m) {
                apply(log2(m), 2, function(x){mean(x[feature.subset[[i]]])})
            })
        }
        set.rev <- unlist(feat.result, recursive=FALSE) # Unlist once to aggregate samples
        p.copy <- p
        for (i in 1:length(set.rev))
        {
            p.copy[[i]] <- as.data.frame(p.copy[[i]])
            p[[i]] <- apply(log2(p.copy[[i]]),1, function(x){ x - (set.rev[[i]])})
            p[[i]] <- t(p[[i]])
        }
        l2p <- p    # Save the set in order to generate the aldex.clr variable
    }


    # sanity check on data
    for ( i in 1:length(l2p) ) {
        if ( any( ! is.finite( l2p[[i]] ) ) ) stop("non-finite log-frequencies were unexpectedly computed")
    }
if (verbose == TRUE) print("clr transformation complete")

    return(new("aldex.clr",reads=reads,mc.samples=mc.samples,verbose=verbose,useMC=useMC,analysisData=l2p))
}


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Getters
###

setMethod("getMonteCarloInstances", signature(.object="aldex.clr"), function(.object) .object@analysisData)

setMethod("getSampleIDs", signature(.object="aldex.clr"), function(.object) names(.object@analysisData))

setMethod("getFeatures", signature(.object="aldex.clr"), function(.object) .object@analysisData[[1]][,1])

setMethod("numFeatures", signature(.object="aldex.clr"), function(.object) length(.object@analysisData[[1]][,1]))

setMethod("numMCInstances", signature(.object="aldex.clr"), function(.object) length(.object@analysisData[[1]][1,]))

setMethod("getFeatureNames", signature(.object="aldex.clr"), function(.object) rownames(.object@analysisData[[1]]))

setMethod("getReads", signature(.object="aldex.clr"), function(.object) .object@reads)

setMethod("numConditions", signature(.object="aldex.clr"), function(.object) length(names(.object@analysisData)))

setMethod("getMonteCarloReplicate", signature(.object="aldex.clr",i="numeric"), function(.object,i) .object@analysisData[[i]])

setMethod("aldex.clr", signature(reads="data.frame"), function(reads, conds, mc.samples=128, denom="all", verbose=FALSE, useMC=FALSE) aldex.clr.function(reads, conds, mc.samples, denom, verbose, useMC, summarizedExperiment=FALSE))

setMethod("aldex.clr", signature(reads="matrix"), function(reads, conds, mc.samples=128, denom="all", verbose=FALSE, useMC=FALSE) aldex.clr.function(as.data.frame(reads), conds, mc.samples, denom, verbose, useMC, summarizedExperiment=FALSE))

setMethod("aldex.clr", signature(reads="RangedSummarizedExperiment"), function(reads, conds, mc.samples=128, denom="all", verbose=FALSE, useMC=FALSE) aldex.clr.function(reads, conds, mc.samples, denom, verbose, useMC, summarizedExperiment=TRUE))


