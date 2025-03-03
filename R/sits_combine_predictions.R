#' @title Estimate ensemble prediction based on list of probs cubes
#'
#' @name  sits_combine_predictions
#'
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#' @author Rolf Simoes, \email{rolf.simoes@@inpe.br}
#'
#' @param  cubes             List of probability data cubes.
#' @param  type              Method to measure uncertainty. See details.
#' @param  ...               Parameters for specific functions.
#' @param  uncert_cubes      Uncertainty cubes to be used as local weights.
#' @param  multicores        Number of cores to run the function.
#' @param  memsize           Maximum overall memory (in GB) to run the
#'                           function.
#' @param  output_dir        Output directory for image files.
#' @param  version           Version of resulting image.
#'                           (in the case of multiple tests)
#' @return A combined probability cube
#'
#' @description Calculate an ensemble predictor based a list of probability
#' cubes. The function combines the output of two or more classifier
#' to derive a value which is based on weights assigned to each model.
#' The supported types of ensemble predictors are 'average' and
#' 'uncertainty'.
#'
#' @note
#' Please refer to the sits documentation available in
#' <https://e-sensing.github.io/sitsbook/> for detailed examples.
#'
#' @examples
#' if (sits_run_examples()) {
#'     # create a data cube from local files
#'     data_dir <- system.file("extdata/raster/mod13q1", package = "sits")
#'     cube <- sits_cube(
#'         source = "BDC",
#'         collection = "MOD13Q1-6",
#'         data_dir = data_dir,
#'         delim = "_",
#'         parse_info = c("X1", "tile", "band", "date")
#'     )
#'     # create a random forest model
#'     rfor_model <- sits_train(samples_modis_ndvi, sits_rfor())
#'     # classify a data cube using rfor model
#'     probs_rfor_cube <- sits_classify(data = cube, ml_model = rfor_model)
#'     # create an XGBoost model
#'     xgb_model <- sits_train(samples_modis_ndvi, sits_xgboost())
#'     # classify a data cube using xgboost model
#'     probs_xgb_cube <- sits_classify(data = cube, ml_model = xgb_model)
#'     # create a list of predictions to be combined
#'     pred_cubes <- list(probs_rfor_cube, probs_xgb_cube)
#'     # combine predictions
#'     comb_probs_cube <- sits_combine_predictions(cubes = pred_cubes)
#'     # plot the resulting combined prediction cube
#'     plot(comb_probs_cube)
#' }
#' @export
sits_combine_predictions <- function(cubes, type = "average", ...,
                                     multicores = 2,
                                     memsize = 8,
                                     output_dir = ".",
                                     version = "v1") {
    # set caller to show in errors
    .check_set_caller("sits_combine_predictions")
    # check required packages
    .check_require_packages("parallel")
    # precondition - multicores
    .check_multicores(multicores)
    # precondition - memsize
    .check_memsize(memsize)
    # precondition - output dir
    .check_output_dir(output_dir)
    # precondition - version
    .check_version(version)
    # define the class of the smoothing
    class(type) <- c(type, class(type))
    UseMethod("sits_combine_predictions", type)
}

#' @rdname sits_combine_predictions
#'
#' @export
#'
sits_combine_predictions.average <- function(cubes,
                                             type = "average", ...,
                                             multicores = 2,
                                             memsize = 4,
                                             output_dir = getwd(),
                                             version = "v1") {


    # is every cube a probs cube
    purrr::map(cubes, .check_is_probs_cube)
    # check if cubes match
    .check_cube_list_match(cubes)

    # get number of labels
    n_labels <- length(sits_labels(cubes[[1]]))
    scale_factor <- .conf("probs_cube_scale_factor")
    # average probability calculation
    .do_average <- function(chunk_lst) {
        data_lst <- purrr::map(chunk_lst, function(chunk){
            # convert probabilities matrix to INT2U
            values <- .raster_get_values(r_obj = chunk)
            values <- scale_factor * values
            return(values)
        })
        # process combination
        ave_probs <- average_probs(data_lst)
        # create cube
        res <- .raster_rast(
            r_obj = chunk_lst[[1]],
            nlayers = n_labels
        )
        # copy values
        scale_factor_save <- round(1./scale_factor)
        res <- .raster_set_values(
            r_obj = res,
            values = round(ave_probs * scale_factor_save, digits = 0)
        )
        return(res)
    }

    # compute which block size is many tiles to be computed
    block_size <- .comb_estimate_block_size(
        cubes  = cubes,
        multicores = multicores,
        memsize = memsize
    )

    # start parallel processes
    .sits_parallel_start(workers = multicores, log = FALSE)
    on.exit(.sits_parallel_stop())

    # process each brick layer (each time step) individually
    blocks_tile_lst <- slider::pslide(cubes, function(...) {
        tile_lst <- list(...)
        tile <- tile_lst[[1]]
        # create metadata for raster cube
        tile_new <- .cube_derived_create(
            tile       = tile,
            cube_class = "probs_cube",
            band_name  = "probs",
            labels     = .tile_labels(tile),
            start_date = .tile_start_date(tile),
            end_date   = .tile_end_date(tile),
            bbox       = .bbox(tile),
            output_dir = output_dir,
            version    = version
        )

        # prepare output filename
        out_file <- .tile_path(tile_new)

        # if file exists skip it (resume feature)
        if (file.exists(out_file)) {
            if (all(.raster_bbox(.raster_open_rast(out_file))
                    == sits_bbox(tile_new))) {
                message(paste0(
                    "Recovery mode: probability image file found in '",
                    dirname(out_file), "' directory. ",
                    "(If you want a new probability image, please ",
                    "change the directory in the 'output_dir' or the ",
                    "value of 'version' parameter)"
                ))
                return(NULL)
            }
        }

        # for now, only vertical blocks are allowed, i.e. 'x_blocks' is 1
        blocks <- .comb_compute_blocks(
            xsize = .tile_ncols(tile),
            ysize = .tile_nrows(tile),
            block_y_size = block_size[["block_y_size"]],
            overlapping_y_size = 0
        )


        # open probability files
        in_file_lst <- purrr::map(tile_lst, .tile_path)

        # process blocks in parallel
        block_files_lst <- .sits_parallel_map(blocks, function(block) {

            # open brick
            chunk_lst <- purrr::map(in_file_lst, function(in_file){
                b <- .raster_open_rast(in_file)

                # crop adding overlaps
                temp_chunk_file <- .file_block_name(
                    pattern = "chunk_combine_av_",
                    block = block,
                    output_dir = output_dir
                )
                chunk <- .raster_crop(
                    r_obj = b,
                    file = temp_chunk_file,
                    data_type = .raster_data_type(
                        .conf("probs_cube_data_type")
                    ),
                    overwrite = TRUE,
                    block = block
                )
                return(chunk)
            })
            # process it
            raster_out <- .do_average(chunk_lst = chunk_lst)

            block_file <- .file_block_name(
                pattern = "chunk_combine_ave_out_",
                block = block,
                output_dir = output_dir
            )
            .raster_write_rast(
                r_obj = raster_out,
                file = block_file,
                data_type = .conf("probs_cube_data_type"),
                overwrite    = TRUE
            )
            # Delete temp file
            purrr::map(chunk_lst, function(temp_chunk_file){
                unlink(.raster_sources(temp_chunk_file))
            })
            return(block_file)
        })

        block_files <- unlist(block_files_lst)

        return(invisible(block_files))
    })


    # process each brick layer (each time step) individually
    result_cube <- .sits_parallel_map(seq_along(blocks_tile_lst), function(i) {

        # get tile from cube
        tile <- cubes[[1]][i, ]

        # create metadata for raster cube
        tile_new <- .cube_derived_create(
            tile       = tile,
            cube_class = "probs_cube",
            band_name  = "probs",
            labels     = .tile_labels(tile),
            start_date = .tile_start_date(tile),
            end_date   = .tile_end_date(tile),
            bbox       = .bbox(tile),
            output_dir = output_dir,
            version    = version
        )

        # prepare output filename
        out_file <- .tile_path(tile_new)

        # if file exists skip it (resume feature)
        if (file.exists(out_file)) {
            return(tile_new)
        }

        block_files <- blocks_tile_lst[[i]]

        # apply function to blocks
        on.exit(unlink(block_files))

        # Merge final result
        .raster_merge_blocks(
            out_files = out_file,
            base_file = .tile_path(tile),
            block_files = block_files,
            data_type = .conf("probs_cube_data_type"),
            missing_value = .conf("probs_cube_missing_value"),
            multicores = 1
        )

        return(tile_new)
    })

    # bind rows
    result_cube <- dplyr::bind_rows(result_cube)

    class(result_cube) <- unique(c("probs_cube", class(cubes[[1]])))

    return(result_cube)
}

#' @rdname sits_combine_predictions
#'
#' @export
#'
sits_combine_predictions.uncertainty <- function(cubes,
                                                 type = "uncertainty", ...,
                                                 uncert_cubes,
                                                 multicores = 2,
                                                 memsize = 4,
                                                 output_dir = getwd(),
                                                 version = "v1") {
    # check if probs cubes and uncert cubes are valid and match
    # is every cube a probs cube
    purrr::map(cubes, .check_is_probs_cube)
    # check if cubes match
    .check_cube_list_match(cubes)
    # all uncert cubes are valid
    purrr::map(uncert_cubes, .check_cube_is_uncert_cube)
    .check_cube_list_match(uncert_cubes)
    # check if probs and uncert cubes match
    .check_cubes_match(cubes[[1]], uncert_cubes[[1]])

    # get number of labels
    n_labels <- length(sits_labels(cubes[[1]]))
    scale_factor <- .conf("probs_cube_scale_factor")
    # average probability calculation
    .do_uncert <- function(prob_chunk_lst, unc_chunk_lst) {
        prob_lst <- purrr::map(prob_chunk_lst, function(chunk){
            # convert probabilities matrix to INT2U
            values <- .raster_get_values(r_obj = chunk)
            values <- scale_factor * values
            return(values)
        })
        unc_lst <- purrr::map(unc_chunk_lst, function(chunk){
            # convert probabilities matrix to INT2U
            values <- .raster_get_values(r_obj = chunk)
            values <- scale_factor * values
            return(values)
        })
        # process combination
        ave_probs <- weighted_uncert_probs(prob_lst, unc_lst)
        # create cube
        res <- .raster_rast(
            r_obj = prob_chunk_lst[[1]],
            nlayers = n_labels
        )
        # copy values
        scale_factor_save <- round(1./scale_factor)
        res <- .raster_set_values(
            r_obj = res,
            values = round(ave_probs * scale_factor_save, digits = 0)
        )
        return(res)
    }

    # compute which block size is many tiles to be computed
    block_size <- .comb_estimate_block_size(
        cubes  = cubes,
        multicores = multicores,
        memsize = memsize,
        uncert = TRUE
    )

    # start parallel processes
    .sits_parallel_start(workers = multicores, log = FALSE)
    on.exit(.sits_parallel_stop())

    # process each brick layer (each time step) individually

    blocks_tile_lst <- purrr::map(seq_len(nrow(cubes[[1]])), function(i) {
        tile <- cubes[[1]][i,]
        # create metadata for raster cube
        tile_new <- .cube_derived_create(
            tile       = tile,
            cube_class = "probs_cube",
            band_name  = "probs",
            labels     = .tile_labels(tile),
            start_date = .tile_start_date(tile),
            end_date   = .tile_end_date(tile),
            bbox       = .bbox(tile),
            output_dir = output_dir,
            version    = version
        )

        # prepare output filename
        out_file <- .tile_path(tile_new)

        # if file exists skip it (resume feature)
        if (file.exists(out_file)) {
            if (all(.raster_bbox(.raster_open_rast(out_file))
                    == sits_bbox(tile_new))) {
                message(paste0(
                    "Recovery mode: probability image file found in '",
                    dirname(out_file), "' directory. ",
                    "(If you want a new probability image, please ",
                    "change the directory in the 'output_dir' or the ",
                    "value of 'version' parameter)"
                ))
                return(NULL)
            }
        }

        # for now, only vertical blocks are allowed, i.e. 'x_blocks' is 1
        blocks <- .comb_compute_blocks(
            xsize = .tile_ncols(tile),
            ysize = .tile_nrows(tile),
            block_y_size = block_size[["block_y_size"]],
            overlapping_y_size = 0
        )
        tile_lst <- purrr::map(cubes, function(cube){
            return(cube[i,])
        } )
        tile_unc_lst <- purrr::map(uncert_cubes, function(cube_unc){
            return(cube_unc[i,])
        })
        # open probability files
        in_file_lst <- purrr::map(tile_lst, .tile_path)
        # open uncert files
        in_file_unc_lst <- purrr::map(tile_unc_lst, .tile_path)

        # process blocks in parallel
        block_files_lst <- .sits_parallel_map(blocks, function(block) {

            # open brick
            prob_chunk_lst <- purrr::map(in_file_lst, function(in_file) {
                b <- .raster_open_rast(in_file)

                # crop adding overlaps
                temp_chunk_file <- .file_block_name(
                    pattern = "chunk_combine_unc_",
                    block = block,
                    output_dir = output_dir
                )
                chunk <- .raster_crop(
                    r_obj = b,
                    file = temp_chunk_file,
                    data_type = .raster_data_type(
                        .conf("probs_cube_data_type")
                    ),
                    overwrite = TRUE,
                    block = block
                )
                return(chunk)
            })
            unc_chunk_lst <- purrr::map(in_file_unc_lst, function(in_unc_file){

                b <- .raster_open_rast(in_unc_file)

                # crop adding overlaps

                temp_chunk_file <- .file_block_name(
                    pattern = "chunk_combine_unc_out_",
                    block = block,
                    output_dir = output_dir
                )
                chunk <- .raster_crop(
                    r_obj = b,
                    file = temp_chunk_file,
                    data_type = .raster_data_type(
                        .conf("probs_cube_data_type")
                    ),
                    overwrite = TRUE,
                    block = block
                )
                return(chunk)
            })
            # process it
            raster_out <- .do_uncert(prob_chunk_lst = prob_chunk_lst,
                                     unc_chunk_lst  = unc_chunk_lst)

            block_file <- .file_block_name(
                pattern = "chunk_combine_no_over_",
                block = block,
                output_dir = output_dir
            )
            .raster_write_rast(
                r_obj = raster_out,
                file = block_file,
                data_type = .conf("probs_cube_data_type"),
                overwrite    = TRUE
            )
            # Delete temp file
            purrr::map(prob_chunk_lst, function(temp_chunk_file){
                unlink(.raster_sources(temp_chunk_file))
            })
            purrr::map(unc_chunk_lst, function(temp_chunk_file){
                unlink(.raster_sources(temp_chunk_file))
            })
            return(block_file)
        })

        block_files <- unlist(block_files_lst)
        return(invisible(block_files))
    })

    # process each brick layer (each time step) individually
    result_cube <- .sits_parallel_map(seq_along(blocks_tile_lst), function(i) {

        # get tile from cube
        tile <- cubes[[1]][i, ]

        # create metadata for raster cube
        tile_new <- .cube_derived_create(
            tile       = tile,
            cube_class = "probs_cube",
            band_name  = "probs",
            labels     = .tile_labels(tile),
            start_date = .tile_start_date(tile),
            end_date   = .tile_end_date(tile),
            bbox       = .bbox(tile),
            output_dir = output_dir,
            version    = version
        )

        # prepare output filename
        out_file <- .tile_path(tile_new)

        # if file exists skip it (resume feature)
        if (file.exists(out_file)) {
            return(tile_new)
        }

        block_files <- blocks_tile_lst[[i]]

        # Merge final result
        .raster_merge_blocks(
            out_files = out_file,
            base_file = .tile_path(tile),
            block_files = block_files,
            data_type = .conf("probs_cube_data_type"),
            missing_value = .conf("probs_cube_missing_value"),
            multicores = 1
        )

        # Remove blocks
        on.exit(unlink(block_files), add = TRUE)

        return(tile_new)
    })

    # bind rows
    result_cube <- dplyr::bind_rows(result_cube)

    class(result_cube) <- unique(c("probs_cube", class(cubes[[1]])))

    return(result_cube)
}


#' @title Estimate the number of blocks to run .sits_split_cluster
#' @name .comb_estimate_block_size
#' @keywords internal
#' @noRd
#'
#' @param cubes        List of input data cube
#' @param multicores   number of processes to split up the data
#' @param memsize      maximum overall memory size (in GB)
#' @param uncert       include uncertainty cubes?
#'
#' @return  returns a list with following information:
#'          multicores theoretical upper bound;
#'          block x_size (horizontal) and y_size (vertical)
#'
.comb_estimate_block_size <- function(cubes,
                                      multicores,
                                      memsize,
                                      uncert = FALSE) {

    cube <- cubes[[1]]
    n_comb <- length(cubes)

    n_layers <- length(cube$labels[[1]])
    bloat_mem <- .conf("processing_bloat")
    n_bytes <- 8

    # include uncertainty cubes?
    if (uncert)
        n_layers <- n_layers + n_comb

    # total memory needed in GB
    image_size <- .tile_ncols(cube) * .tile_nrows(cube)
    needed_memory <- n_comb * image_size * 1E-09 * n_layers * bloat_mem * n_bytes

    # minimum block size
    min_block_x_size <- .tile_ncols(cube) # for now, only vertical blocking
    min_block_y_size <- 1

    # compute factors
    memory_factor <- needed_memory / memsize

    blocking_factor <- image_size / (min_block_x_size * min_block_y_size)

    # stop if blocking factor is less than memory factor!
    # reason: the provided memory is not enough to process the data by
    # breaking it into small chunks
    .check_that(
        x = memory_factor <= blocking_factor,
        msg = "provided memory not enough to run the job"
    )

    # update multicores to the maximum possible processes given the available
    # memory and blocking factor
    multicores <- min(floor(blocking_factor / memory_factor), multicores)

    # compute blocking allocation that maximizes the
    # block / (memory * multicores) ratio, i.e. maximize parallel processes
    # and returns the following information:
    # - multicores theoretical upper bound;
    # - block x_size (horizontal) and y_size (vertical)
    blocks <- list(
        # theoretical max_multicores = floor(blocking_factor / memory_factor),
        block_x_size = floor(min_block_x_size),
        block_y_size = min(
            floor(blocking_factor / memory_factor / multicores),
            .tile_nrows(cube)
        )
    )

    return(blocks)
}

#' @name .comb_compute_blocks
#' @description Function to compute blocks grid
#' @keywords internal
#' @noRd
#'
#' @param xsize        X size of the image
#' @param ysize        Y size of the image
#' @param block_y_size Y size of the block
#' @param overlapping_y_size   Size of the overlap
#' @return  A list of blocks
#'
.comb_compute_blocks <- function(xsize,
                                 ysize,
                                 block_y_size,
                                 overlapping_y_size) {
    r1 <- seq(1, ysize - 1, by = block_y_size)
    r2 <- c(r1[-1] - 1, ysize)
    nr1 <- r2 - r1 + 1
    ovr_r1 <- c(1, c(r1[-1] - overlapping_y_size))
    ovr_r2 <- c(r2[-length(r2)] + overlapping_y_size, ysize)
    ovr_nr1 <- ovr_r2 - ovr_r1 + 1

    # define each block as a list element
    blocks <- mapply(
        list,
        row = ovr_r1,
        nrows = ovr_nr1,
        col = 1,
        ncols = xsize,
        crop_row = r1 - ovr_r1 + 1,
        crop_nrows = nr1,
        crop_col = 1,
        crop_ncols = xsize,
        SIMPLIFY = FALSE
    )

    return(blocks)
}
