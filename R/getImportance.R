#' Get variable importance
#'
#' This function computes the permutation importance of each variable in each model, by shuffling each variable in turn (a given number of times) and computing the root mean squared difference between the actual model predictions and those obtained with the shuffled variable. Values are then normalized to a percentage by dividing each by the sum of all values and multiplying by 100.
#' Note that "importance" is not a straightforward concept and it can be measured in many different ways. Permutation importance is a widely used and effective model-agnostic technique, which provides an intuitive measure of the contribution of each variable, particularly in complex and non-linear models.
#'
#' @param mods output of [getModels()].
#' @param nper integer value (default 10; increase for more accurate but computationally intensive results) indicating the number of permutations for shuffling each variable.
#' @param verbosity integer value indicating the amount of messages to display. The default is 2, for the maximum number of messages available.
#' @param plot logical value specifying whether to produce a line (spaghetti) plot of the mean importance of each variable along the periods. Note that this plot does not reflect the deviations around this mean, and that it may become hard to read if there are many variables or if their importances overlap.
#' @param palette argument to pass to [hcl.colors()] specifying the colours for the lines (if plot=TRUE). The default is "Dark2"; run hcl.pals() for other options.
#' @param \dots additional arguments that can be passed to [base::plot()], e.g. 'main', 'xlab', 'ylab' or 'las'.
#'
#' @return A data frame with the permutation importance (expressed as percentage) of each variable in each model replicate for each period, along with the cross-replicate mean and standard deviation. If plot=TRUE (the default), also a spaghetti plot of mean variable importance per period.
#'
#' @seealso \code{varImportance} in package \pkg{predicts}; \code{bm_VariablesImportance} in package \pkg{biomod2}
#'
#' @author A. Marcia Barbosa
#' @export
#' @importFrom stats sd
#' @importFrom grDevices hcl.colors
#'
#' @examples
#' # Several data prep steps required.
#' # See https://github.com/AMBarbosa/ecotrends for a full worked example.


getImportance <- function(mods, nper = 10, verbosity = 2, plot = TRUE, palette = "Dark2", ...) {

  models <- mods$models
  n_periods <- length(models)
  n_reps <- length(models[[1]])

  varimps <- vector("list", n_periods)
  names(varimps) <- names(models)

  for (y in 1:n_periods) {
    period <- names(models)[y]

    if (verbosity > 0) {
      if (n_reps <= 1)
        message("computing period ", y, " of ", n_periods, ": ", period)
      else
        message("computing period ", y, " of ", n_periods, " (with replicates): ", period)
    }  # end if verbosity

    dat <- mods$data[ , grep(period, names(mods$data))]
    varimps[[y]] <- vector("list", length(models[[y]]))
    names(varimps[[y]]) <- names(models[[y]])

    for (r in 1:n_reps){
      # varimps[[y]][[r]] <- predicts::varImportance(models[[y]][[r]], y = mods$data$presence, x = dat, n = nper, stat = "RMSE", type = "cloglog")
      varimps[[y]][[r]] <- varImpor(models[[y]][[r]], data = dat, nper = nper)
    }  # end for r

    varimps[[y]] <- do.call(cbind.data.frame, varimps[[y]])
  }  # end for y

  varimps <- do.call(rbind.data.frame, varimps)
  varimps$mean <- apply(varimps, 1, mean)
  varimps$sd <- apply(varimps, 1, sd)

  # move period and variable from row names to new columns:
  splits <- strsplit(rownames(varimps), "\\.")
  varimps <- data.frame(period = sapply(splits, getElement, 1),
                        variable = sapply(splits, getElement, 2),
                        varimps)
  rownames(varimps) <- NULL
  varimps$period <- as.numeric(varimps$period)

  if (plot) {
    vars <- substr(varimps$variable, 1, nchar(varimps$variable) - 5)  # remove period from variable names
    clrs <- hcl.colors(n = length(unique(vars)), palette = palette, alpha = 0.9)

    Period <- range(varimps$period)
    Mean_importance <- range(varimps$mean)  # names for default axis labels
    plot(x = Period, y = Mean_importance,
         type = "n", bty = "n", ...)

    for (v in unique(vars)) {
      clr <- clrs[which(vars == v)]
      dat <- varimps[vars == v, ]
      lines(dat$period, dat$mean, col = clr)
      text(x = dat$period[nrow(dat)],
           y = dat$mean[nrow(dat)],  # last value
           labels = v, pos = 4,  # to the right of the last value
           cex = 0.8, col = clr, xpd = NA)  # note text overlaps may occur
    } # end for v
  }  # end if plot

  return(varimps)
}


varImpor <- function(model, data, nper) {
  original_predictions <- as.vector(predict(model, data, type = "cloglog"))

  varimps <- numeric(ncol(data))

  for (v in seq_along(varimps)) {
    permuted_scores <- numeric(nper)

    for (p in 1:nper) {
      permuted_data <- data
      permuted_data[, v] <- sample(permuted_data[, v])
      permuted_predictions <- as.vector(predict(model, permuted_data, type = "cloglog"))
      permuted_scores[p] <- sqrt(mean((original_predictions - permuted_predictions)^2))  # RMSE
    }

    varimps[v] <- mean(permuted_scores)
  }  # end for v

  # normalize and convert to percentage:
  varimps <- varimps / sum(varimps) * 100

  names(varimps) <- colnames(data)

  return(varimps)
}
