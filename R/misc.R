# Map R classes to handsontable.js types
get_col_types = function(data) {
  if (is.matrix(data))  {
    types = rep(typeof(data), ncol(data))
  } else if (is.data.frame(data)){
    types = as.character(lapply(data, class))
  } else{
    stop("Unsupported object type: ", class(data), " Can't extract column types.")
  }

  types <- sapply(types, function(type) {
    if (grepl("factor", type)) return("factor")

    switch(type,
           integer="integer",
           double="numeric",
           numeric="numeric",
           character="text",
           logical="checkbox",
           Date="date",
           "text")
  })

  as.character(types)
}

# Convert handsontable to R object
toR = function(data, changes, params, ...) {
  rClass = params$rClass
  colHeaders = unlist(params$rColHeaders)
  rowHeaders = unlist(params$rRowHeaders)
  rColClasses = unlist(params$rColClasses)[colHeaders]

  out = data

  # copy/paste may add rows without firing an afterCreateRow event (still needed?)
  # if (length(out) != length(rowHeaders))
  #   changes$event = "afterCreateRow"

  # remove spare empty rows; autofill fix (not working)
  # if (!is.null(changes$source) && changes$source == "autofill") {
  #   rm_inds = sapply(out, function(x) all(unlist(x) == "NA"))
  #   rm_inds = suppressWarnings(min(which(diff(rm_inds) == -1)))
  #   if (rm_inds != Inf)
  #     out = out[-(length(out) - rm_inds + 1)]
  # }

  # pre-conversion updates; afterCreateCol moved to end of function
  # if (changes$event == "afterCreateRow") {
  #   inds = seq(changes$ind + 1, length.out = changes$ct)
  #   # prevent duplicates
  #   nm = 1
  #   while (nm %in% rowHeaders) {
  #     nm = nm + 1
  #   }
  #   rowHeaders = c(head(rowHeaders, inds - 1), nm,
  #                  tail(rowHeaders, length(rowHeaders) - inds + 1))
  # } else if (changes$event == "afterRemoveRow") {
  #   inds = seq(changes$ind + 1, length.out = changes$ct)
  #   rowHeaders = rowHeaders[-inds]
  if (changes$event == "afterRemoveCol") {
    if (!("matrix" %in% rClass)) {
      inds = seq(changes$ind + 1, 1, length.out = changes$ct)
      rColClasses = rColClasses[-inds]
    }
  }

  # convert
  if ("matrix" %in% rClass) {
    nr = length(out)
    out = unlist(out, recursive = FALSE)
    # replace NULL with NA
    out = unlist(lapply(out, function(x) if (is.null(x)) NA else x))

    # If there is no data create empty matrix
    if (length(out) == 0) {
      out = matrix(nrow = 0, ncol = length(colHeaders))
    } else {
      out = matrix(out, nrow = nr, byrow = TRUE)
    }

    class(out) = params$rColClasses

  } else if ("data.frame" %in% rClass) {
    nr = length(out)

    out = unlist(out, recursive = FALSE)
    # replace NULL with NA
    out = unlist(lapply(out, function(x) if (is.null(x)) NA else x))

    # If there is no data create empty matrix
    if (length(out) == 0) {
      out = matrix(nrow = 0, ncol = length(colHeaders))
    } else {
      out = matrix(out, nrow = nr, byrow = TRUE)
    }

    out = colClasses(as.data.frame(out, stringsAsFactors = FALSE),
                     rColClasses, params$columns, ...)
  } else {
    stop("Conversion not implemented: ", rClass)
  }


  # post-conversion updates
  if (changes$event == "afterCreateRow") {
    # default logical NA in data.frame to FALSE
    if (!("matrix" %in% rClass)) {
      inds_logical = which(rColClasses == "logical")
      for (i in inds_logical)
        out[[i]] = ifelse(is.na(out[[i]]), FALSE, out[[i]])
    }
  }

  if (ncol(out) != length(colHeaders))
    colHeaders = genColHeaders(changes, colHeaders)

  if (nrow(out) != length(rowHeaders) && !is.null(rowHeaders))
    rowHeaders = genRowHeaders(changes, rowHeaders)

  colnames(out) = colHeaders
  rownames(out) = rowHeaders

  if ("data.table" %in% rClass)
    out = as(out, "data.table")

  out
}

# Coerces data.frame columns to the specified classes
# see http://stackoverflow.com/questions/9214819/supply-a-vector-to-classes-of-dataframe
colClasses <- function(d, colClasses, cols, date_fmt = "%m/%d/%Y", ...) {
  colClasses <- rep(colClasses, len=length(d))
  for(i in seq_along(d))
    d[[i]] = switch(
      colClasses[i],
      Date = as.Date(d[[i]], origin='1970-01-01',
                     format = date_fmt),
      POSIXct = as.POSIXct(d[[i]], origin='1970-01-01',
                           format = date_fmt),
      factor = factor(d[[i]],
                      levels = c(unlist(cols[[i]]$source),
                                 unique(d[[i]][!(d[[i]] %in% unlist(cols[[i]]$source))])),
                      ordered = TRUE),
      json = jsonlite::toJSON(d[[i]]),
      suppressWarnings(as(d[[i]], colClasses[i])))
  d
}

genColHeaders <- function(changes, colHeaders) {
  ind_ct = length(which(grepl("V[0-9]{1,}", colHeaders)))

  if (changes$event == "afterRemoveCol") {
    colHeaders[-(seq(changes$ind, length = changes$ct) + 1)]
  } else if (changes$event == "afterCreateCol") {
    # create new column names
    new_cols = paste0("V", changes$ct + ind_ct)
    # insert into vector
    inds = seq(changes$ind + 1, 1, length.out = changes$ct)
    c(colHeaders, new_cols)[order(c(seq_along(colHeaders), inds - 0.5))]
  } else {
    stop("Change no recognized:", changes$event)
  }
}

genRowHeaders <- function(changes, rowHeaders) {
  inds = seq(changes$ind + 1, length.out = changes$ct)

  if (changes$event == "afterCreateRow") {
    # prevent duplicates
    nm = 1
    while (nm %in% rowHeaders) {
      nm = nm + 1
    }
    c(head(rowHeaders, inds - 1), nm,
      tail(rowHeaders, length(rowHeaders) - inds + 1))
  } else if (changes$event == "afterRemoveRow") {
    rowHeaders[-inds]
  }
}
