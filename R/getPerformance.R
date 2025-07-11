#' Get model performance
#'
#' @param rasts SpatRasterDataset output of [getPredictions()], or 'file' argument previously provided to [getPredictions()]
#' @param mods output of [getModels()]
#' @param metrics character vector with the metrics to compute. Can be any subset (default all) of c("AUC", "TSS", "kappa"), with the latter two computed at their maximum values (optimal thresholds). Performance metrics are computed with presence against all background (using 'modEvA' package functions with pbg=TRUE), so they evaluate the capacity of distinguishing presence from random, rather than presence from absence pixels (Phillips et al., 2006).
#' @param plot logical value indicating whether plots should also be produced to illustrate the performance metrics for each model. The default is FALSE; TRUE can be slow for large datasets.
#' @param verbosity integer value indicating the amount of messages to display. The default is 2, for the maximum number of messages available.
#'
#' @return This function returns a data frame of the performance evaluation results for each model.
#' @export
#' @importFrom terra mask nlyr sds vect
#' @importFrom modEvA AUC getThreshold optiThresh threshMeasures
#'
#' @references
#' Phillips, S.J., Anderson, R.P., Schapire, R.E. (2006) Maximum entropy modeling of species geographic distributions. Ecological Modelling, 190: 231-259. https://doi.org/10.1016/j.ecolmodel.2005.03.026
#'
#' @examples
#' # Several data prep steps required.
#' # See https://github.com/AMBarbosa/ecotrends for a full worked example.


getPerformance <- function(rasts, mods, metrics = c("AUC", "TSS", "kappa"), plot = FALSE, verbosity = 2) {

  # if (plot) {
  #   opar <- par(no.readonly = TRUE)
  #   on.exit(par(opar))
  #   par(mfrow = c(2, length(metrics)))
  # }  # may crash RStudio if user resizes plot window mid-process

  if (is.character(rasts)) {  # file path
    rast_files <- list.files(rasts, full.names = TRUE)
    rasts <- terra::sds(rast_files)
  }

  data <- mods$data

  bg_coords <- terra::vect(data[ , c("x", "y")], geom = c("x", "y"),
                           crs = terra::crs(rasts[[1]]))

  # if (inherits(rasts, "SpatRaster")) {  # no replicates
  #   pres_coords <- data[data$presence == 1, c("x", "y")]
  #   rasts_mask <- terra::mask(rasts, bg_coords)
  #   n_periods <- terra::nlyr(rasts)
  #   # perf <- matrix(data = NA, nrow = n_periods, ncol = length(metrics))
  #   # colnames(perf) <- metrics
  #
  # } else {  # with replicates, 'rasts' is a SpatRasterDataset

  rasts_mask <- lapply(rasts, terra::mask, bg_coords)
  n_periods <- length(rasts)

  n_reps <- terra::nlyr(rasts[[1]])
  # perf <- matrix(data = NA, nrow = n_periods * n_reps, ncol = length(metrics))
  # colnames(perf) <- sort(paste0(metrics, c("_train", "_test")))
  reps <- gsub("rep", "", names(mods$models[[1]]))
  n <- length(rasts)
  out <- data.frame(period = rep(names(rasts), each = n_reps), rep = rep(reps, n), train_presences = rep(NA_integer_, n), test_presences = rep(NA_integer_, n))
  if ("AUC" %in% metrics) out <- data.frame(out, train_AUC = rep(NA_real_, n), test_AUC = rep(NA_real_, n))
  if ("TSS" %in% metrics) out <- data.frame(out, train_TSS = rep(NA_real_, n), train_thresh_TSS = rep(NA_real_, n), test_TSS = rep(NA_real_, n), test_thresh_TSS = rep(NA_real_, n))
  if ("kappa" %in% metrics) out <- data.frame(out, train_kappa = rep(NA_real_, n), train_thresh_kappa = rep(NA_real_, n), test_kappa = rep(NA_real_, n), test_thresh_kappa = rep(NA_real_, n))


  # }  # end if reps


  for (y in 1:n_periods) {
    period <- names(rasts)[y]

    if (verbosity > 0) {
      if (n_reps <= 1)
        message("evaluating period ", y, " of ", n_periods, ": ", period)
      else
        message("evaluating period ", y, " of ", n_periods, " (with replicates): ", period)
    }

    # if (inherits(rasts, "SpatRaster")) {  # no replicates
    #   if ("AUC" %in% metrics) {
    #     perf[y, "AUC"] <- modEvA::AUC(obs = pres_coords, pred = rasts_mask[[y]], simplif = TRUE, plot = plot, main = period, verbosity = 0, pbg = TRUE)
    #   }
    #
    #   if ("TSS" %in% metrics) {
    #     if (isFALSE(plot)) {
    #       perf[y, "train_TSS"] <- modEvA::threshMeasures(obs = pres_coords, pred = rasts_mask[[y]], simplif = TRUE, measures = "TSS", thresh = "maxTSS", standardize = FALSE, plot = FALSE, verbosity = 0, pbg = TRUE)[1, 1]
    #     } else {
    #       tss <- modEvA::optiThresh(obs = pres_coords, pred = rasts_mask[[y]], measures = "TSS", pch = 20, cex = 0.3, main = period, verbosity = 0, pbg = TRUE)$optimals.criteria[1, 1]
    #       perf[y, "train_TSS"] <- tss
    #       text(0.5, 0.05, substitute(paste(maxTSS == a), list(a = round(tss, 3))))
    #     } # end if plot
    #   }  # end if TSS
    #
    #   out <- data.frame(period = names(rasts), perf)
    #
    # } else {  # if replicates

    for (r in 1:length(mods$models[[y]])) {

      # data[data$presence == 1 && data[ , paste0("pres_rep", r)] == 0, ] <- NA  # no, as this doesn't seem to be what Maxent normally does

      rep_colname <- paste0("pres_", names(mods$models[[1]])[r])  # for rep0
      if (!(rep_colname) %in% names(data))  data[ , rep_colname] <- data$presence

      pres_train <- data[data[ , rep_colname] == 1, c("x", "y")]  # presences that were used in the replicate
      pres_test <- data[data[ , rep_colname] == 0 & data[ , "presence"] == 1, c("x", "y")]  # presences that were left out of the replicate
      out[ , "train_presences"] <- nrow(pres_train)
      out[ , "test_presences"] <- nrow(pres_test)

      flag <- FALSE
      if (r != sub("pres_rep", "", rep_colname)) {  # for rep0
        flag <- TRUE
        out$rep <- 1  # for 'out$rep == r' below; converted back to 0 in the end if flag TRUE
      }

      if ("AUC" %in% metrics) {
        out[out$period == period & out$rep == r, "train_AUC"] <- modEvA::AUC(obs = pres_train, pred = rasts_mask[[y]][[r]], simplif = TRUE, plot = plot, main = paste0(period, "_rep", r, "_train"), verbosity = 0, pbg = TRUE)
        if (nrow(pres_test) > 0) {
          out[out$period == period & out$rep == r, "test_AUC"] <- modEvA::AUC(obs = pres_test, pred = rasts_mask[[y]][[r]], simplif = TRUE, plot = plot, main = paste0(period, "_rep", r, "_test"), verbosity = 0, pbg = TRUE)
        } else {
          out[out$period == period & out$rep == r, "test_AUC"] <- NA
        }
      }  # end if AUC

      if ("TSS" %in% metrics) {
        if (isFALSE(plot)) {
          train_threshold <- modEvA::getThreshold(obs = pres_train, pred = rasts_mask[[y]][[r]], threshMethod = "maxTSS", na.rm = TRUE, verbosity = 0, pbg = TRUE)
          if (nrow(pres_test) > 0)
            test_threshold <- modEvA::getThreshold(obs = pres_test, pred = rasts_mask[[y]][[r]], threshMethod = "maxTSS", na.rm = TRUE, verbosity = 0, pbg = TRUE)
          else
            test_threshold <- NA

          out[out$period == period & out$rep == r, "train_TSS"] <- modEvA::threshMeasures(obs = pres_train, pred = rasts_mask[[y]][[r]], simplif = TRUE, measures = "TSS", thresh = train_threshold, standardize = FALSE, plot = FALSE, verbosity = 0, pbg = TRUE)[1, 1]
          if (nrow(pres_test) > 0)
            out[out$period == period & out$rep == r, "test_TSS"] <- modEvA::threshMeasures(obs = pres_test, pred = rasts_mask[[y]][[r]], simplif = TRUE, measures = "TSS", thresh = test_threshold, standardize = FALSE, plot = FALSE, verbosity = 0, pbg = TRUE)[1, 1]
          else
            out[out$period == period & out$rep == r, "test_TSS"] <- NA

          out[out$period == period & out$rep == r, "train_thresh_TSS"] <- train_threshold
          if (nrow(pres_test) > 0)
            out[out$period == period & out$rep == r, "test_thresh_TSS"] <- test_threshold
          else
            out[out$period == period & out$rep == r, "test_thresh_TSS"] <- NA

        } else {  # if plot
          train_TSS <- modEvA::optiThresh(obs = pres_train, pred = rasts_mask[[y]][[r]], measures = "TSS", pch = 20, cex = 0.3, main = paste0(period, "_rep", r, "_train"), sep.plots = NA, reset.par = FALSE, verbosity = 0, pbg = TRUE)
          text(0.5, 0.05, substitute(paste(maxTSS == a), list(a = round(train_TSS$optimals.each[1, "value"], 3))))
          out[out$period == period & out$rep == r, "train_TSS"] <- train_TSS$optimals.each[1, "value"]
          out[out$period == period & out$rep == r, "train_thresh_TSS"] <- train_TSS$optimals.each[1, "threshold"]

          if (nrow(pres_test) > 0) {
            test_TSS <- modEvA::optiThresh(obs = pres_test, pred = rasts_mask[[y]][[r]], measures = "TSS", pch = 20, cex = 0.3, main = paste0(period, "_rep", r, "_test"), sep.plots = NA, reset.par = FALSE, verbosity = 0, pbg = TRUE)
            text(0.5, 0.05, substitute(paste(maxTSS == a), list(a = round(test_TSS$optimals.each[1, "value"], 3))))
            out[out$period == period & out$rep == r, "test_TSS"] <- test_TSS$optimals.each[1, "value"]
            out[out$period == period & out$rep == r, "test_thresh_TSS"] <- test_TSS$optimals.each[1, "threshold"]
          } else out[out$period == period & out$rep == r, "test_TSS"] <- out[out$period == period & out$rep == r, "test_thresh_TSS"] <- NA
        } # end if plot
      }  # end if TSS

      if ("kappa" %in% metrics) {
        if (isFALSE(plot)) {
          train_threshold <- modEvA::getThreshold(obs = pres_train, pred = rasts_mask[[y]][[r]], threshMethod = "maxKappa", na.rm = TRUE, verbosity = 0, pbg = TRUE)
          if (nrow(pres_test) > 0)
            test_threshold <- modEvA::getThreshold(obs = pres_test, pred = rasts_mask[[y]][[r]], threshMethod = "maxKappa", na.rm = TRUE, verbosity = 0, pbg = TRUE)
          else
            test_threshold <- NA

          out[out$period == period & out$rep == r, "train_kappa"] <- modEvA::threshMeasures(obs = pres_train, pred = rasts_mask[[y]][[r]], simplif = TRUE, measures = "kappa", thresh = train_threshold, standardize = FALSE, plot = FALSE, verbosity = 0, pbg = TRUE)[1, 1]
          if (nrow(pres_test) > 0)
            out[out$period == period & out$rep == r, "test_kappa"] <- modEvA::threshMeasures(obs = pres_test, pred = rasts_mask[[y]][[r]], simplif = TRUE, measures = "kappa", thresh = test_threshold, standardize = FALSE, plot = FALSE, verbosity = 0, pbg = TRUE)[1, 1]
          else
            out[out$period == period & out$rep == r, "test_kappa"] <- NA

          out[out$period == period & out$rep == r, "train_thresh_kappa"] <- train_threshold
          if (nrow(pres_test) > 0)
            out[out$period == period & out$rep == r, "test_thresh_kappa"] <- test_threshold
          else
            out[out$period == period & out$rep == r, "test_thresh_kappa"] <- NA

        } else {  # if plot
          train_kappa <- modEvA::optiThresh(obs = pres_train, pred = rasts_mask[[y]][[r]], measures = "kappa", pch = 20, cex = 0.3, main = paste0(period, "_rep", r, "_train"), sep.plots = NA, reset.par = FALSE, verbosity = 0, pbg = TRUE)
          text(0.5, 0.05, substitute(paste(maxKappa == a), list(a = round(train_kappa$optimals.each[1, "value"], 3))))
          out[out$period == period & out$rep == r, "train_kappa"] <- train_kappa$optimals.each[1, "value"]
          out[out$period == period & out$rep == r, "train_thresh_kappa"] <- train_kappa$optimals.each[1, "threshold"]

          if (nrow(pres_test) > 0) {
            test_kappa <- modEvA::optiThresh(obs = pres_test, pred = rasts_mask[[y]][[r]], measures = "kappa", pch = 20, cex = 0.3, main = paste0(period, "_rep", r, "_test"), sep.plots = NA, reset.par = FALSE, verbosity = 0, pbg = TRUE)
            text(0.5, 0.05, substitute(paste(maxKappa == a), list(a = round(test_kappa$optimals.each[1, "value"], 3))))
            out[out$period == period & out$rep == r, "test_kappa"] <- test_kappa$optimals.each[1, "value"]
            out[out$period == period & out$rep == r, "test_thresh_kappa"] <- test_kappa$optimals.each[1, "threshold"]
          } else out[out$period == period & out$rep == r, "test_kappa"] <- out[out$period == period & out$rep == r, "test_thresh_kappa"] <- NA
        } # end if plot
      }  # end if kappa

    }  # end for r

    # }  # end if reps
  }  # end for y

  if (isTRUE(flag))
    out$rep <- 0

  return(out)
}
