### =========================================================================
### Comparing, ordering, and tabulating vector-like objects
### -------------------------------------------------------------------------
###


### Functions/operators for comparing, ordering, tabulating:
###
###     pcompare
###     ==
###     !=
###     <=
###     >=
###     <
###     >
###     sameAsPreviousROW
###     match
###     selfmatch
###     duplicated
###     anyDuplicated
###     unique
###     %in%
###     findMatches
###     countMatches
###     order
###     sort
###     rank
###     xtfrm
###     table


### Method signatures for binary comparison operators.
.OP2_SIGNATURES <- list(
    c("Vector", "Vector"),
    c("Vector", "ANY"),
    c("ANY", "Vector")
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Element-wise (aka "parallel") comparison of 2 Vector objects.
###

setGeneric("pcompare", function(x, y) standardGeneric("pcompare"))

setMethod("pcompare", c("numeric", "numeric"), function(x, y) {
    as.integer(sign(x - y))
})

setMethod("pcompare", c("ANY", "ANY"), function(x, y) {
    combined <- bindROWS(x, list(y))
    original <- c(seq_len(NROW(x)), seq_len(NROW(y)))
    is.x <- rep(c(TRUE, FALSE), c(NROW(x), NROW(y)))

    o <- order(combined)
    original <- original[o]
    is.x <- is.x[o]

    grouping <- cumsum(!sameAsPreviousROW(extractROWS(combined, o)))
    x.groups <- integer(NROW(x))
    x.groups[original[is.x]] <- grouping[is.x]
    y.groups <- integer(NROW(y))
    y.groups[original[!is.x]] <- grouping[!is.x]

    pcompare(x.groups, y.groups)
})

### The methods below are implemented on top of pcompare().

setMethods("==", .OP2_SIGNATURES,
    function(e1, e2) { pcompare(e1, e2) == 0L }
)

setMethods("<=", .OP2_SIGNATURES,
    function(e1, e2) { pcompare(e1, e2) <= 0L }
)

### The methods below are implemented on top of == and <=.

setMethods("!=", .OP2_SIGNATURES, function(e1, e2) { !(e1 == e2) })

setMethods(">=", .OP2_SIGNATURES, function(e1, e2) { e2 <= e1 })

setMethods("<", .OP2_SIGNATURES, function(e1, e2) { !(e2 <= e1) })

setMethods(">", .OP2_SIGNATURES, function(e1, e2) { !(e1 <= e2) })


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Comparisons along the ROWS
###
### Provides a basic implementation of what is different between ROWS.
###
### The default "sameAsPreviousROW" method below is implemented on top
### of ==.
###

setGeneric("sameAsPreviousROW",
    function(x) standardGeneric("sameAsPreviousROW")
)

setMethod("sameAsPreviousROW", "ANY", function(x) {
    if (NROW(x)==0) {
        logical(0)
    } else {
        c(FALSE, tail(x, n=-1L) == head(x, n=-1L))
    }
})

.nasafe_compare <- function(z, y) {
    comp <- z==y
    na.z <- is.na(z)
    na.y <- is.na(y)
    comp[na.z!=na.y] <- FALSE
    comp[na.z & na.y] <- TRUE
    comp
}

.atomic_sameAsPreviousROW <- function(x) {
    if (NROW(x)==0) {
        logical(0)
    } else {
        z <- head(x, n=-1L) 
        y <- tail(x, n=-1L)
        c(FALSE, .nasafe_compare(z, y))
    }
}

setMethod("sameAsPreviousROW", "atomic", .atomic_sameAsPreviousROW)

# Explicitly define this to avoid dispatching to the numeric method
# and suffering the unnecessary is.nan() checks.
setMethod("sameAsPreviousROW", "integer", .atomic_sameAsPreviousROW)

.numeric_sameAsPreviousROW <- function(x) {
    if (NROW(x)==0) {
        logical(0)
    } else {
        z <- head(x, n=-1L) 
        y <- tail(x, n=-1L)
        comp <- .nasafe_compare(z, y)

        # No need to test for '&' to set to TRUE here, 
        # as NaN equality is covered by NA equality.
        nan.z <- is.nan(z)
        nan.y <- is.nan(y)
        comp[nan.z!=nan.y] <- FALSE

        c(FALSE, comp)
    }
}

setMethod("sameAsPreviousROW", "numeric", .numeric_sameAsPreviousROW)

setMethod("sameAsPreviousROW", "complex", .numeric_sameAsPreviousROW)

### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### match()
###
### The default "match" method below is implemented on top of
### selfmatch().
###

setMethod("match", c("Vector", "Vector"),
    function(x, table, nomatch = NA_integer_, incomparables = NULL, ...) 
{
    # table goes first so it gets picked up by 'selfmatch'.
    combined <- bindROWS(table, list(x))

    # Do NOT use nomatch=nomatch here, we need the NAs as a marker.
    ans <- selfmatch(combined, nomatch=NA_integer_, incomparables=incomparables)
    ans <- tail(ans, NROW(x))
    ans[is.na(ans) | ans > NROW(table)] <- nomatch
    ans
})


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### selfmatch()
###
### The default "selfmatch" method below is implemented on top of match().
###

setGeneric("selfmatch", function(x, ...) standardGeneric("selfmatch"))

### Default "selfmatch" method. Args in ... are propagated to match().
setMethod("selfmatch", "ANY", function(x, ...) match(x, x, ...))

### Optimized "selfmatch" method for factors.
setMethod("selfmatch", "factor", function(x, ..., incomparables = NULL) {
    ignore.na <- isTRUE(is.na(incomparables))
    has.incomparables <- !is.null(incomparables) && !ignore.na
    if (!missing(...) || has.incomparables || (!ignore.na && anyNA(x)) ||
          is.unsorted(x))
        callNextMethod()
    else as.integer(x)
})

### Vector-based "selfmatch" method, slightly more efficient than match(x, x).
setMethod("selfmatch", "Vector", function(x, nomatch = NA_integer_, incomparables = NULL, ...) {
    if (NROW(x)==0L) return(integer(0))

    g <- grouping(x)
    ends <- attr(g, "ends")
    starts <- c(1L, head(ends, -1L) + 1L)
    first.of.kind <- g[starts]

    if (!is.null(incomparables)) {
        # %in% should call match() with incomparables=NULL,
        # otherwise we get an infinite loop of S4 dispatch!
        first.x <- extractROWS(x, first.of.kind)
        first.of.kind[first.x %in% incomparables] <- nomatch
    }

    ans <- integer(NROW(x))
    ans[g] <- rep(first.of.kind, ends - starts + 1L)
    ans
})

### 'selfmatch_mapping' must be an integer vector like one returned by
### selfmatch(), that is, values are non-NAs and such that any value 'v' in it
### must appear for the first time at *position* 'v'.
### Such a vector can be seen as a many-to-one mapping that maps any position
### in the vector to a lower position and that has the additional property of
### being idempotent.
### More formally, any vector returned by selfmatch() has the 2 following
### properties:
###
###   (1) for any 1 <= i <= length(selfmatch_mapping),
###           selfmatch_mapping[i] must be >= 1 and <= i
### and
###
###   (2) selfmatch_mapping[selfmatch_mapping] is the same as selfmatch_mapping
###
### reverseSelfmatchMapping() creates the "reverse mapping" as an ordinary
### list.
reverseSelfmatchMapping <- function(selfmatch_mapping)
{
    ans <- vector(mode="list", length=length(selfmatch_mapping))
    sparse_ans <- split(seq_along(selfmatch_mapping), selfmatch_mapping)
    ans[as.integer(names(sparse_ans))] <- as.list(sparse_ans)
    ans
}


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### duplicated() & anyDuplicated() & unique()
###
### The "duplicated" method below is implemented on top of selfmatch().
### The "anyDuplicated" and "unique" methods below are implemented on top
### of duplicated().
###

### S3/S4 combo for duplicated.Vector
duplicated.Vector <- function(x, incomparables=FALSE, ...)
    duplicated(x, incomparables=incomparables, ...)

.duplicated.Vector <- function(x, incomparables=FALSE, ...)
{
    if (!identical(incomparables, FALSE))
        stop("the \"duplicated\" method for Vector objects ",
             "only accepts 'incomparables=FALSE'")
    args <- list(...)
    if ("fromLast" %in% names(args)) {
        fromLast <- args$fromLast
        if (!isTRUEorFALSE(fromLast))
            stop("'fromLast' must be TRUE or FALSE")
        args$fromLast <- NULL
        if (fromLast)
            x <- rev(x)
    } else {
        fromLast <- FALSE
    }
    xx <- do.call(selfmatch, c(list(x), args))
    ans <- xx != seq_along(xx)
    if (fromLast)
        ans <- rev(ans)
    ans
}
setMethod("duplicated", "Vector", .duplicated.Vector)

### S3/S4 combo for anyDuplicated.Vector
anyDuplicated.Vector <- function(x, incomparables=FALSE, ...)
    anyDuplicated(x, incomparables=incomparables, ...)
.anyDuplicated.Vector <- function(x, incomparables=FALSE, ...)
{
    if (!identical(incomparables, FALSE))
        stop("the \"anyDuplicated\" method for Vector objects ",
             "only accepts 'incomparables=FALSE'")
    any(duplicated(x, incomparables=incomparables, ...))
}
setMethod("anyDuplicated", "Vector", .anyDuplicated.Vector)

### S3/S4 combo for unique.Vector
unique.Vector <- function(x, incomparables=FALSE, ...)
    unique(x, incomparables=incomparables, ...)
.unique.Vector <- function(x, incomparables=FALSE, ...)
{
    if (!identical(incomparables, FALSE))
        stop("the \"unique\" method for Vector objects ",
             "only accepts 'incomparables=FALSE'")
    i <- !duplicated(x, incomparables=incomparables, ...)
    extractROWS(x, i)
}
setMethod("unique", "Vector", .unique.Vector)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### %in%
###
### The method below is implemented on top of match().
###

setMethods("%in%", .OP2_SIGNATURES,
    function(x, table) { match(x, table, nomatch=0L) > 0L }
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### findMatches() & countMatches()
###
### The default "findMatches" and "countMatches" methods below are
### implemented on top of match().
###

setGeneric("findMatches", signature=c("x", "table"),
    function(x, table, select=c("all", "first", "last"), ...)
        standardGeneric("findMatches")
)

### Equivalent to 'countQueryHits(findMatches(x, table))' but the default
### "countMatches" method below has a more efficient implementation.
setGeneric("countMatches", signature=c("x", "table"),
    function(x, table, ...)
        standardGeneric("countMatches")
)

### Problem: using transpose=TRUE generates an invalid SortedByQueryHits
### object (hits are not sorted by query):
###   > S4Vectors:::.findAllMatchesInSmallTable(1:6, c(7:5, 4:5),
###                                             transpose=TRUE)
###   Hits of length 4
###   queryLength: 5
###   subjectLength: 6
###     queryHits subjectHits
###      <integer>   <integer>
###    1         4           4
###    2         3           5
###    3         5           5
###    4         2           6
### and the cost of ordering them would probably defeat the purpose of the
### "put the smallest object on the right" optimization trick.
.findAllMatchesInSmallTable <- function(x, table, ..., transpose=FALSE)
{
    x2 <- match(x, table, ...)
    table2 <- selfmatch(table, ...)
    table_low2high <- reverseSelfmatchMapping(table2)
    hits_per_x <- table_low2high[as.integer(x2)]
    x_hits <- rep.int(seq_along(hits_per_x), sapply_NROW(hits_per_x))
    if (length(x_hits) == 0L) {
        table_hits <- integer(0)
    } else {
        table_hits <- unlist(hits_per_x, use.names=FALSE)
    }
    if (transpose) {
        Hits(table_hits, x_hits, length(table), length(x), sort.by.query=TRUE)
    } else {
        Hits(x_hits, table_hits, length(x), length(table), sort.by.query=TRUE)
    }
}

### Default "findMatches" method. Args in ... are propagated to match() and
### selfmatch().
setMethod("findMatches", c("ANY", "ANY"),
    function(x, table, select=c("all", "first", "last"), ...)
    {
        select <- match.arg(select)
        if (select != "all")
            stop("'select' is not supported yet. Note that you can use ",
                 "match() if you want to do 'select=\"first\"'. Otherwise ",
                 "you're welcome to request this on the Bioconductor ",
                 "mailing list.")
        ## "put the smallest object on the right" optimization trick
        #if (length(x) < length(table))
        #    return(.findAllMatchesInSmallTable(table, x, ..., transpose=TRUE))
        .findAllMatchesInSmallTable(x, table, ...)
    }
)

setMethod("findMatches", c("ANY", "missing"),
    function(x, table, select=c("all", "first", "last"), ...)
    {
        ans <- callGeneric(x, x, select=select, ...)
        if (!is(ans, "Hits"))  # e.g. if 'select' is "first"
            return(ans)
        as(ans, "SortedByQuerySelfHits")
    }
)

### Default "countMatches" method. Args in ... are propagated to match() and
### selfmatch().
.countMatches.default <- function(x, table, ...)
{
    x_len <- length(x)
    table_len <- length(table)
    if (x_len <= table_len) {
        table2 <- match(table, x, ...)  # can contain NAs
        nbins <- x_len
        x2 <- selfmatch(x, ...)  # no NAs
    } else {
        table2 <- selfmatch(table, ...)  # no NAs
        nbins <- table_len + 1L
        x2 <- match(x, table, nomatch=nbins, ...)
    }
    tabulate(table2, nbins=nbins)[x2]
}

setMethod("countMatches", c("ANY", "ANY"), .countMatches.default)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### sort()
###
### The method below is implemented on top of order().
###

sort.Vector <- function(x, decreasing=FALSE, ...)
    sort(x, decreasing=decreasing, ...)
setMethod("sort", "Vector", .sort.Vector)

formulaAsListCall <- function(formula) {
    attr(terms(formula), "variables")
}

formulaValues <- function(x, formula) {
    listCall <- formulaAsListCall(formula)
    vals <- eval(listCall, as.env(x, environment(formula)))
    names(vals) <- vapply(listCall, function(x) {
        paste(deparse(x, width.cutoff = 500), collapse = " ")
    }, character(1L))[-1L]
    vals
}

orderBy <- function(formula, x, decreasing=FALSE, na.last=TRUE) {
  values <- formulaValues(x, formula)
  do.call(order, c(decreasing=decreasing, na.last=na.last, values))
}

setMethod("rank", "Vector",
    function(x, na.last=TRUE,
             ties.method=c("average", "first", "last", "random", "max", "min"),
             by)
    {
        ties.method <- match.arg(ties.method)
        if (!missing(by))
            oo <- orderBy(by, x, na.last=na.last)
        else oo <- order(x, na.last=na.last)
        ## 'ans' is the reverse permutation of 'oo'.
        ans <- integer(length(oo))
        ans[oo] <- seq_along(oo)
        if (ties.method == "first")
            return(ans)
        ans <- ans[selfmatch(x)]
        if (ties.method == "min")
            return(ans)
        ## Other ties methods.
        rank(ans, ties.method=ties.method)
    }
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### xtfrm()
###
### The method below is implemented on top of order().
###

setMethod("xtfrm", "Vector", function(x) {
    o <- order(x)
    y <- extractROWS(x, o)
    is.unique <- !sameAsPreviousROW(y)
    out.rank <- cumsum(is.unique)
    out.rank[o] <- out.rank
    out.rank
})


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### table()
###
### The method below is implemented on top of selfmatch(), order(), and
### as.character().
###

### This is a copy/paste of the list.names() function locally defined inside
### base::table().
.list.names <- function(...) {
    deparse.level <- 1
    l <- as.list(substitute(list(...)))[-1L]
    nm <- names(l)
    fixup <- if (is.null(nm))
        seq_along(l)
    else nm == ""
    dep <- vapply(l[fixup], function(x) switch(deparse.level +
        1, "", if (is.symbol(x)) as.character(x) else "",
        deparse(x, nlines = 1)[1L]), "")
    if (is.null(nm))
        dep
    else {
        nm[fixup] <- dep
        nm
    }
}

### Works on any object for which selfmatch(), order(), and as.character()
### are supported.
.compute_table <- function(x)
{
    xx <- selfmatch(x)
    t <- tabulate(xx, nbins=length(xx))
    keep_idx <- which(t != 0L)
    x2 <- x[keep_idx]
    t2 <- t[keep_idx]
    oo <- order(x2)
    x2 <- x2[oo]
    t2 <- t2[oo]
    ans <- array(t2)
    ## Some "as.character" methods propagate the names (e.g. the method for
    ## GenomicRanges objects). We drop them.
    dimnames(ans) <- list(unname(as.character(x2)))
    ans
}

setMethod("table", "Vector",
    function(...)
    {
        args <- list(...)
        if (length(args) != 1L)
            stop("\"table\" method for Vector objects ",
                 "can only take one input object")
        x <- args[[1L]]

        ## Compute the table as an array.
        ans <- .compute_table(x)

        ## Some cosmetic adjustments.
        names(dimnames(ans)) <- .list.names(...)
        class(ans) <- "table"
        ans
    }
)

setMethod("xtabs", signature(data = "Vector"),
          function(formula = ~., data, subset, na.action, exclude = c(NA, NaN),
                   drop.unused.levels = FALSE)
{
    data <- as.env(data, environment(formula), tform=decode)
    callGeneric()
})

