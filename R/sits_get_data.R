#' @title Get time series from data cubes and cloud services
#' @name sits_get_data
#' @author Gilberto Camara
#'
#' @description Retrieve a set of time series from a data cube or from
#' a time series service. Data cubes and puts it in a "sits tibble".
#' Sits tibbles are the main structures of sits package.
#' They contain both the satellite image time series and their metadata.
#'
#' @note
#' There are four ways of specifying data to be retrieved using the
#' \code{samples} parameter:
#' (a) CSV file: a CSV file with columns
#' \code{longitude}, \code{latitude},
#' \code{start_date}, \code{end_date} and \code{label} for each sample;
#' (b) SHP file: a shapefile in POINT or POLYGON geometry
#' containing the location of the samples and an attribute to be
#' used as label. Also, provide start and end date for the time series;
#' (c) sits object: A sits tibble;
#' (d) sf object: An \code{link[sf]{sf}} object with POINT or POLYGON geometry;
#' (e) data.frame: A data.frame with with mandatory columns
#' \code{longitude} and \code{latitude}.
#
#' @param cube            Data cube from where data is to be retrieved.
#'                        (tibble of class "raster_cube").
#' @param samples         Location of the samples to be retrieved.
#'                        Either a tibble of class "sits", an "sf" object,
#'                        the name of a shapefile or csv file, or
#'                        a data.frame with columns "longitude" and "latitude".
#' @param ...             Specific parameters for specific cases.
#' @param start_date      Start of the interval for the time series - optional
#'                        (Date in "YYYY-MM-DD" format).
#' @param end_date        End of the interval for the time series - optional
#'                        (Date in "YYYY-MM-DD" format).
#' @param label           Label to be assigned to the time series (optional)
#'                        (character vector of length 1).
#' @param bands           Bands to be retrieved - optional
#'                        (character vector).
#' @param crs             Default crs for the samples
#'                        (character vector of length 1).
#' @param impute_fn       Imputation function to remove NA.
#' @param label_attr      Attribute in the shapefile or sf object to be used
#'                        as a polygon label.
#'                        (character vector of length 1).
#' @param n_sam_pol       Number of samples per polygon to be read
#'                        for POLYGON or MULTIPOLYGON shapefiles or sf objects
#'                        (single integer).
#' @param pol_avg         Logical: summarize samples for each polygon?
#' @param pol_id          ID attribute for polygons
#'                        (character vector of length 1)
#' @param sampling_type   Spatial sampling type: random, hexagonal,
#'                        regular, or Fibonacci.
#' @param multicores      Number of threads to process the time series
#'                        (integer, with min = 1 and max = 2048).
#' @param progress        Logical: show progress bar?
#'
#' @return A tibble of class "sits" with set of time series
#' <longitude, latitude, start_date, end_date, label>.
#'
#'
#' @examples
#' if (sits_run_examples()) {
#'     # reading a lat/long from a local cube
#'     # create a cube from local files
#'     data_dir <- system.file("extdata/raster/mod13q1", package = "sits")
#'     raster_cube <- sits_cube(
#'         source = "BDC",
#'         collection = "MOD13Q1-6.1",
#'         data_dir = data_dir
#'     )
#'     samples <- tibble::tibble(longitude = -55.66738, latitude = -11.76990)
#'     point_ndvi <- sits_get_data(raster_cube, samples)
#'     #
#'     # reading samples from a cube based on a  CSV file
#'     csv_file <- system.file("extdata/samples/samples_sinop_crop.csv",
#'         package = "sits"
#'     )
#'     points <- sits_get_data(cube = raster_cube, samples = csv_file)
#'
#'     # reading a shapefile from BDC (Brazil Data Cube)
#'     bdc_cube <- sits_cube(
#'             source = "BDC",
#'             collection = "CBERS-WFI-16D",
#'             bands = c("NDVI", "EVI"),
#'             tiles = c("007004", "007005"),
#'             start_date = "2018-09-01",
#'             end_date = "2018-10-28"
#'     )
#'     # define a shapefile to be read from the cube
#'     shp_file <- system.file("extdata/shapefiles/bdc-test/samples.shp",
#'             package = "sits"
#'     )
#'     # get samples from the BDC based on the shapefile
#'     time_series_bdc <- sits_get_data(
#'         cube = bdc_cube,
#'         samples = shp_file
#'     )
#' }
#'
#' @export
sits_get_data <- function(cube,
                          samples, ...) {
    .check_set_caller("sits_get_data")
    # Pre-conditions
    .check_is_raster_cube(cube)
    .check_cube_is_regular(cube)
    .check_raster_cube_files(cube)
    if (is.character(samples)) {
        class(samples) <- c(.file_ext(samples), class(samples))
    }
    UseMethod("sits_get_data", samples)
}
#' @rdname sits_get_data
#'
#' @export
sits_get_data.default <- function(cube, samples, ...) {
    stop(.conf("messages", "sits_get_data_default"))
}

#' @rdname sits_get_data
#' @export
sits_get_data.csv <- function(cube,
                              samples, ...,
                              bands = NULL,
                              crs = "EPSG:4326",
                              impute_fn = impute_linear(),
                              multicores = 2,
                              progress = FALSE) {
    if (!.has(bands))
        bands <- .cube_bands(cube)
    .check_cube_bands(cube, bands = bands)
    .check_crs(crs)
    .check_int_parameter(multicores, min = 1, max = 2048)
    .check_progress(progress)
    .check_function(impute_fn)
    # Extract a data frame from csv
    samples <- .csv_get_samples(samples)
    # Extract time series from a cube given a data.frame
    data <- .data_get_ts(
        cube       = cube,
        samples    = samples,
        bands      = bands,
        crs        = crs,
        impute_fn  = impute_fn,
        multicores = multicores,
        progress   = progress
    )
    return(data)
}
#' @rdname sits_get_data
#' @export
sits_get_data.shp <- function(cube,
                              samples, ...,
                              label = "NoClass",
                              start_date = NULL,
                              end_date = NULL,
                              bands = NULL,
                              impute_fn = impute_linear(),
                              label_attr = NULL,
                              n_sam_pol = 30,
                              pol_avg = FALSE,
                              pol_id = NULL,
                              sampling_type = "random",
                              multicores = 2,
                              progress = FALSE) {
    .check_set_caller("sits_get_data_shp")
    if (!.has(bands))
        bands <- .cube_bands(cube)
    .check_cube_bands(cube, bands = bands)
    # Get default start and end date
    start_date <- .default(start_date, .cube_start_date(cube))
    end_date <- .default(end_date, .cube_end_date(cube))
    .check_int_parameter(multicores, min = 1, max = 2048)
    .check_progress(progress)
    # Pre-condition - shapefile should have an id parameter
    .check_that(!(pol_avg && .has_not(pol_id)))

    # Extract a data frame from shapefile
    samples <- .shp_get_samples(
        shp_file    = samples,
        label       = label,
        shp_attr    = label_attr,
        start_date  = start_date,
        end_date    = end_date,
        n_shp_pol   = n_sam_pol,
        shp_id      = pol_id,
        sampling_type = sampling_type
    )
    # Extract time series from a cube given a data.frame
    data <- .data_get_ts(
        cube       = cube,
        samples    = samples,
        bands      = bands,
        impute_fn  = impute_fn,
        multicores = multicores,
        progress   = progress
    )
    if (pol_avg && "polygon_id" %in% colnames(data)) {
        data <- .data_avg_polygon(data = data)
    }
    return(data)
}

#' @rdname sits_get_data
#' @export
sits_get_data.sf <- function(cube,
                             samples,
                             ...,
                             start_date = NULL,
                             end_date = NULL,
                             bands = NULL,
                             impute_fn = impute_linear(),
                             label = "NoClass",
                             label_attr = NULL,
                             n_sam_pol = 30,
                             pol_avg = FALSE,
                             pol_id = NULL,
                             sampling_type = "random",
                             multicores = 2,
                             progress = FALSE) {
    .check_set_caller("sits_get_data_sf")
    .check_that(!(pol_avg && .has_not(pol_id)))
    if (!.has(bands))
        bands <- .cube_bands(cube)
    .check_cube_bands(cube, bands = bands)
    .check_int_parameter(multicores, min = 1, max = 2048)
    .check_progress(progress)
    .check_function(impute_fn)
    # Get default start and end date
    start_date <- .default(start_date, .cube_start_date(cube))
    end_date <- .default(end_date, .cube_end_date(cube))
    cube <- .cube_filter_interval(
        cube = cube, start_date = start_date, end_date = end_date
    )
    # Extract a samples data.frame from sf object
    samples <- .sf_get_samples(
        sf_object  = samples,
        label      = label,
        label_attr = label_attr,
        start_date = start_date,
        end_date   = end_date,
        n_sam_pol  = n_sam_pol,
        pol_id     = pol_id,
        sampling_type = sampling_type
    )
    # Extract time series from a cube given a data.frame
    data <- .data_get_ts(
        cube       = cube,
        samples    = samples,
        bands      = bands,
        impute_fn  = impute_fn,
        multicores = multicores,
        progress   = progress
    )
    # Do we want an average value per polygon?
    if (pol_avg && "polygon_id" %in% colnames(data)) {
        data <- .data_avg_polygon(data = data)
    }
    return(data)
}
#' @rdname sits_get_data
#' @export
sits_get_data.sits <- function(cube,
                               samples,
                               ...,
                               bands = NULL,
                               crs = "EPSG:4326",
                               impute_fn = impute_linear(),
                               multicores = 2,
                               progress = FALSE) {
    bands <- .default(bands, .cube_bands(cube))
    # Extract time series from a cube given a data.frame
    data <- .data_get_ts(
        cube       = cube,
        samples    = samples,
        bands      = bands,
        impute_fn  = impute_fn,
        multicores = multicores,
        crs        = crs,
        progress   = progress
    )
    return(data)
}
#' @rdname sits_get_data
#'
#' @export
#'
sits_get_data.data.frame <- function(cube,
                                     samples,
                                     ...,
                                     start_date = NULL,
                                     end_date = NULL,
                                     bands = NULL,
                                     label = "NoClass",
                                     crs = "EPSG:4326",
                                     impute_fn = impute_linear(),
                                     multicores = 2,
                                     progress = FALSE) {
    .check_set_caller("sits_get_data_data_frame")
    if (!.has(bands))
        bands <- .cube_bands(cube)
    # Check if samples contains all the required columns
    .check_chr_contains(
        x = colnames(samples),
        contains = c("latitude", "longitude"),
        discriminator = "all_of"
    )
    # Get default start and end date
    start_date <- .default(start_date, .cube_start_date(cube))
    end_date <- .default(end_date, .cube_end_date(cube))
    # Fill missing columns
    if (!.has_column(samples, "label")) {
        samples[["label"]] <- label
    }
    if (!.has_column(samples, "start_date")) {
        samples[["start_date"]] <- start_date
    }
    if (!.has_column(samples, "end_date")) {
        samples[["end_date"]] <- end_date
    }
    # Set samples class
    samples <- .set_class(samples, c("sits", class(samples)))
    # Extract time series from a cube given a data.frame
    data <- .data_get_ts(
        cube       = cube,
        samples    = samples,
        bands      = bands,
        crs        = crs,
        impute_fn  = impute_fn,
        multicores = multicores,
        progress   = progress
    )
    return(data)
}
