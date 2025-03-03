#' @title Get timeline of a cube or a set of time series
#'
#' @name sits_timeline
#'
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description This function returns the timeline for a given data set, either
#'              a set of time series, a data cube, or a trained model.
#'
#' @param  data     either a sits tibble, a data cube, or a trained model.
#'
#' @return      Timeline of sample set or of data cube.
#'
#' @examples
#' sits_timeline(samples_modis_ndvi)
#'
#' @export
#'
sits_timeline <- function(data) {
    .check_set_caller("sits_timeline")
    # get the meta-type (sits or cube)
    data <- .conf_data_meta_type(data)

    UseMethod("sits_timeline", data)
}

#' @export
#'
sits_timeline.sits <- function(data) {
    return(data$time_series[[1]]$Index)
}

#' @export
#'
sits_timeline.sits_model <- function(data) {
    .check_is_sits_model(data)
    samples <- .ml_samples(data)
    return(samples$time_series[[1]]$Index)
}

#' @export
#'
sits_timeline.raster_cube <- function(data) {

    # pick the list of timelines
    timelines.lst <- slider::slide(data, function(tile) {
        timeline_tile <- .tile_timeline(tile)
        return(timeline_tile)
    })
    names(timelines.lst) <- data$tile
    timeline_unique <- unname(unique(timelines.lst))

    if (length(timeline_unique) == 1) {
        return(timeline_unique[[1]])
    } else {
        warning("cube is not regular, returning all timelines", call. = FALSE)
        return(timelines.lst)
    }
}

#' @export
#'
sits_timeline.derived_cube <- function(data) {
    # return the timeline of the cube
    timeline <- .tile_timeline(data)
    return(timeline)
}


#' @title Define the information required for classifying time series
#'
#' @name .timeline_class_info
#'
#' @keywords internal
#' @noRd
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description Time series classification requires a series of steps:
#' (a) Provide labelled samples that will be used as training data.
#' (b) Provide information on how the classification will be performed,
#'     including data timeline,and start and end dates per interval.
#' (c) Clean the training data to ensure it meets the specifications
#'     of the classification info.
#' (d) Use the clean data to train a machine learning classifier.
#' (e) Classify non-labelled data sets.
#'
#' In this set of steps, this function provides support for step (b).
#' It requires the user to provide a timeline, the classification interval,
#' and the start and end dates of the reference period. T
#' he results is a tibble with information that allows the user
#' to perform steps (c) to (e).
#'
#' @param  data            Description on the data being classified.
#' @param  samples         Samples used for training the classification model.
#'
#' @return A tibble with the classification information.
#'
.timeline_class_info <- function(data, samples) {

    # find the timeline
    timeline <- sits_timeline(data)
    # precondition is the timeline correct?
    .check_length(
        x = timeline,
        len_min = 1,
        msg = "sits_timeline_class_info: invalid timeline"
    )
    # find the labels
    labels <- sits_labels(samples)
    # find the bands
    bands <- sits_bands(samples)
    # what is the reference start date?
    ref_start_date <- lubridate::as_date(samples[1, ]$start_date)
    # what is the reference end date?
    ref_end_date <- lubridate::as_date(samples[1, ]$end_date)
    # number of samples
    num_samples <- nrow(samples[1, ]$time_series[[1]])
    # obtain the reference dates that match the patterns in the full timeline
    ref_dates <- .timeline_match(
        timeline,
        ref_start_date,
        ref_end_date,
        num_samples
    )
    # obtain the indexes of the timeline that match the reference dates
    dates_index <- .timeline_match_indexes(timeline, ref_dates)
    # find the number of the samples
    nsamples <- dates_index[[1]][2] - dates_index[[1]][1] + 1
    # create a class_info tibble to be used in the classification
    class_info <- tibble::tibble(
        bands = list(bands),
        labels = list(labels),
        timeline = list(timeline),
        num_samples = nsamples,
        ref_dates = list(ref_dates),
        dates_index = list(dates_index)
    )
    return(class_info)
}

#' @title Test if date fits with the timeline
#'
#' @name .timeline_valid_date
#' @keywords internal
#' @noRd
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description A timeline is a list of dates where observations are available.
#' This function estimates if a date is valid by comparing it to the timeline.
#' If the date's estimate is not inside the timeline and the difference between
#' the date and the first date of timeline is greater than the acquisition
#' interval of the timeline, the date is not valid.
#'
#' @param date        A date.
#' @param timeline    A vector of reference dates.
#'
#' @return Is this is valid starting date?
#'
.timeline_valid_date <- function(date, timeline) {

    # is the date inside the timeline?
    if (date %within% lubridate::interval(
        timeline[1],
        timeline[length(timeline)]
    )) {
        return(TRUE)
    }

    # what is the difference in days between the last two days of the timeline?
    timeline_diff <- as.integer(timeline[2] - timeline[1])
    # if the difference in days in the timeline is smaller than the difference
    # between the reference date and the first date of the timeline, then
    # we assume the date is valid
    if (abs(as.integer(date - timeline[1])) <= timeline_diff) {
        return(TRUE)
    }
    # what is the difference in days between the last two days of the timeline?
    timeline_diff <- as.integer(timeline[length(timeline)] -
        timeline[length(timeline) - 1])

    # if the difference in days in the timeline is smaller than the difference
    # between the reference date and the last date of the timeline, then
    # we assume the date is valid
    if (abs(as.integer(date - timeline[length(timeline)])) <= timeline_diff) {
        return(TRUE)
    }
    return(FALSE)
}

#' @title Find dates in the input data cube that match those of the patterns
#' @name .timeline_match
#' @keywords internal
#' @noRd
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description For correct classification, the input data set
#'              should be aligned to that of the reference data set.
#'              This function aligns these data sets.
#'
#' @param timeline              Timeline of input observations (vector).
#' @param ref_start_date        Reference for starting the classification.
#' @param ref_end_date          Reference for ending the classification.
#' @param num_samples           Number of samples.
#'
#' @return A list of breaks that will be applied to the input data set.
#'
.timeline_match <- function(timeline,
                            ref_start_date,
                            ref_end_date,
                            num_samples) {


    # set caller to show in errors
    .check_set_caller(".timeline_match")

    # make sure the timelines is a valid set of dates
    timeline <- lubridate::as_date(timeline)
    # define the input start and end dates
    input_start_date <- timeline[1]
    # what is the expected start and end dates based on the patterns?
    ref_st_mday <- as.character(lubridate::mday(ref_start_date))
    ref_st_month <- as.character(lubridate::month(ref_start_date))
    year_st_date <- as.character(lubridate::year(input_start_date))
    est_start_date <- lubridate::as_date(paste0(
        year_st_date, "-",
        ref_st_month, "-",
        ref_st_mday
    ))

    # find the actual starting date by searching the timeline
    idx_start_date <- which.min(abs(est_start_date - timeline))
    start_date <- timeline[idx_start_date]
    # is the start date a valid one?
    .check_that(
        x = .timeline_valid_date(start_date, timeline),
        msg = "start date in not inside timeline"
    )

    # obtain the subset dates to break the input data set
    # adjust the dates to match the timeline
    subset_dates <- list()
    # what is the expected end date of the classification?
    idx_end_date <- idx_start_date + (num_samples - 1)
    end_date <- timeline[idx_end_date]
    # is the start date a valid one?
    .check_that(
        x = !(is.na(end_date)),
        msg = paste(
            "start and end date do not match timeline/n",
            "Please compare your timeline with your samples"
        )
    )

    # go through the timeline of the data
    # find the reference dates for the classification
    while (!is.na(end_date)) {
        # add the start and end date
        subset_dates[[length(subset_dates) + 1]] <- c(start_date, end_date)

        # estimate the next start and end dates
        idx_start_date <- idx_end_date + 1
        start_date <- timeline[idx_start_date]
        idx_end_date <- idx_start_date + num_samples - 1
        # estimate
        end_date <- timeline[idx_end_date]
    }
    # is the end date a valid one?
    end_date <- subset_dates[[length(subset_dates)]][2]
    .check_that(
        x = .timeline_valid_date(end_date, timeline),
        msg = "end_date not inside timeline"
    )
    return(subset_dates)
}

#' @title Find indexes in a timeline that match the reference dates
#' @name .timeline_match_indexes
#' @keywords internal
#' @noRd
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description For correct classification, the time series of the input data
#'              should be aligned to that of the reference data set
#'              (usually a set of patterns).
#'              This function aligns these data sets so that shape
#'              matching works correctly
#'
#' @param timeline      Timeline of input observations (vector).
#' @param ref_dates     List of breaks to be applied to the input data set.
#'
#' @return              A list of indexes that match the reference dates
#'                      to the timelines.
#'
.timeline_match_indexes <- function(timeline, ref_dates) {
    dates_index <- ref_dates %>%
        purrr::map(function(date_pair) {
            start_index <- which(timeline == date_pair[1])
            end_index <- which(timeline == date_pair[2])

            dates_index <- c(start_index, end_index)
            return(dates_index)
        })

    return(dates_index)
}
#' @title Find the subset of a timeline that is contained
#'        in an interval defined by start_date and end_date
#' @name  .timeline_during
#' @noRd
#' @keywords internal
#'
#' @param timeline      A valid timeline
#' @param start_date    A date which encloses the start of timeline
#' @param end_date      A date which encloses the end of timeline
#'
#' @return              A timeline
#'
.timeline_during <- function(timeline,
                             start_date = NULL,
                             end_date = NULL) {

    # set caller to show in errors
    .check_set_caller(".sits_timeline_during")
    # obtain the start and end indexes
    if (purrr::is_null(start_date)) {
        start_date <- timeline[1]
    }
    if (purrr::is_null(end_date)) {
        end_date <- timeline[length(timeline)]
    }
    valid <- timeline >= lubridate::as_date(start_date) &
        timeline <= lubridate::as_date(end_date)
    .check_that(
        x = any(valid),
        msg = paste("no valid data between", start_date, "and", end_date)
    )
    return(timeline[valid])
}

#' @title Find if the date information is correct
#' @name  .timeline_format
#' @keywords internal
#' @noRd
#' @description Given a information about dates, check if the date can be
#'              interpreted by lubridate
#' @param date   a date information
#' @return date class vector
#'
.timeline_format <- function(date) {

    # set caller to show in errors
    .check_set_caller(".timeline_format")
    .check_length(
        x = date,
        len_min = 1,
        msg = "invalid date parameter"
    )
    # check type of date interval
    converted_date <- purrr::map_dbl(date, function(dt) {
        if (length(strsplit(dt, "-")[[1]]) == 1) {
            converted_date <- lubridate::fast_strptime(dt, "%Y")
        } else if (length(strsplit(dt, "-")[[1]]) == 2) {
            converted_date <- lubridate::fast_strptime(dt, "%Y-%m")
        } else {
            converted_date <- lubridate::fast_strptime(dt, "%Y-%m-%d")
        }
        # transform to date object
        converted_date <- lubridate::as_date(converted_date)
        # check if there are NAs values
        .check_that(
            x = !is.na(converted_date),
            msg = paste0("invalid date format '", dt, "' in file name")
        )
        return(converted_date)
    })

    # convert to a vector of dates
    converted_date <- lubridate::as_date(converted_date)
    # post-condition
    .check_length(
        x = converted_date,
        len_min = length(date),
        len_max = length(date),
        msg = "invalid date values"
    )
    return(converted_date)
}

#' @title Checks that the timeline of all time series of a data set are equal
#' @name .timeline_check
#' @keywords internal
#' @noRd
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description This function tests if all time series in a sits tibble
#' have the same number of samples
#'
#' @param  data  Either a sits tibble
#' @return       TRUE if the length of time series is unique
#'
.timeline_check <- function(data) {
    if (length(unique(lapply(data$time_series, nrow))) == 1) {
        return(TRUE)
    } else {
        return(FALSE)
    }
}
