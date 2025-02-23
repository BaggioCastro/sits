test_that("Downloading and cropping cubes from BDC", {
    cube <- tryCatch(
        {
            sits_cube(
                source = "BDC",
                collection = "CB4_64_16D_STK-1",
                tiles = c("022024", "022025"),
                bands = c("B15", "CLOUD"),
                start_date = "2018-01-01",
                end_date = "2018-01-12"
            )
        },
        error = function(e) {
            return(NULL)
        }
    )
    testthat::skip_if(
        purrr::is_null(cube),
        "BDC is not accessible"
    )

    cube_local_roi <- sits_cube_copy(
        cube = cube,
        output_dir = tempdir(),
        roi = c(lon_min = -42.28469009,
                lat_min = -14.95411527,
                lon_max = -41.74745556,
                lat_max = -14.65950650),
        multicores = 2
    )

    # Comparing tiles
    expect_equal(nrow(cube), nrow(cube_local_roi))
    bbox_tile <- sits_bbox(cube)
    bbox_crop <- sits_bbox(cube_local_roi)
    # Comparing bounding boxes
    expect_lt(bbox_tile[["xmin"]], bbox_crop[["xmin"]])
    expect_lt(bbox_tile[["ymin"]], bbox_crop[["ymin"]])
    expect_gt(bbox_tile[["xmax"]], bbox_crop[["xmax"]])
    expect_gt(bbox_tile[["ymax"]], bbox_crop[["ymax"]])
    # Comparing classes
    expect_equal(class(cube), class(cube_local_roi))
    # Comparing timelines
    expect_equal(sits_timeline(cube), sits_timeline(cube_local_roi))
    # Comparing X resolution
    expect_equal(cube[["file_info"]][[1]][["xres"]][[1]],
                 cube_local_roi[["file_info"]][[1]][["xres"]][[1]])
    # Comparing Y resolution
    expect_equal(cube[["file_info"]][[1]][["yres"]][[1]],
                 cube_local_roi[["file_info"]][[1]][["yres"]][[1]])
    unlink(sapply(cube_local_roi[["file_info"]], `[[`, "path"))

    cube_local_roi_tr <- sits_cube_copy(
        cube = cube,
        output_dir = tempdir(),
        res = 128,
        roi = c(lon_min = -42.28469009,
                lat_min = -14.95411527,
                lon_max = -41.74745556,
                lat_max = -14.65950650),
        multicores = 2
    )

    # Comparing tiles
    expect_equal(nrow(cube), nrow(cube_local_roi_tr))
    # Comparing bounding boxes
    bbox_roi_tr <- sits_bbox(cube_local_roi_tr)
    expect_lt(bbox_tile[["xmin"]], bbox_roi_tr[["xmin"]])
    expect_lt(bbox_tile[["ymin"]], bbox_roi_tr[["ymin"]])
    expect_gt(bbox_tile[["xmax"]], bbox_roi_tr[["xmax"]])
    expect_gt(bbox_tile[["ymax"]], bbox_roi_tr[["ymax"]])
    # Comparing classes
    expect_equal(class(cube), class(cube_local_roi_tr))
    # Comparing timelines
    expect_equal(sits_timeline(cube), sits_timeline(cube_local_roi_tr))
    # Comparing X resolution
    expect_lt(cube[["file_info"]][[1]][["xres"]][[1]],
              cube_local_roi_tr[["file_info"]][[1]][["xres"]][[1]])
    # Comparing Y resolution
    expect_lt(cube[["file_info"]][[1]][["yres"]][[1]],
              cube_local_roi_tr[["file_info"]][[1]][["yres"]][[1]])
    unlink(sapply(cube_local_roi_tr[["file_info"]], `[[`, "path"))
})

test_that("Downloading entire images from local cubes", {
    data_dir <- system.file("extdata/raster/mod13q1", package = "sits")

    cube <- tryCatch(
        {
            sits_cube(
                source = "BDC",
                collection = "MOD13Q1-6",
                data_dir = data_dir,
                delim = "_",
                parse_info = c("X1", "tile", "band", "date"),
                multicores = 2
            )
        },
        error = function(e) {
            return(NULL)
        }
    )

    testthat::skip_if(purrr::is_null(cube),
                      message = "LOCAL cube not found"
    )

    cube_local <- sits_cube_copy(
        cube = cube,
        output_dir = tempdir()
    )

    # Comparing tiles
    expect_equal(nrow(cube), nrow(cube_local))
    bbox_tile <- sits_bbox(cube, TRUE)
    bbox_cube <- sits_bbox(cube_local, TRUE)
    # Comparing bounding boxes
    expect_equal(bbox_tile[["xmin"]], bbox_cube[["xmin"]])
    expect_equal(bbox_tile[["ymin"]], bbox_cube[["ymin"]])
    expect_equal(bbox_tile[["xmax"]], bbox_cube[["xmax"]])
    expect_equal(bbox_tile[["ymax"]], bbox_cube[["ymax"]])
    # Comparing classes
    expect_equal(class(cube), class(cube_local))
    # Comparing timelines
    expect_equal(sits_timeline(cube), sits_timeline(cube_local))
    # Comparing X resolution
    expect_equal(cube[["file_info"]][[1]][["xres"]][[1]],
                 cube_local[["file_info"]][[1]][["xres"]][[1]])
    # Comparing Y resolution
    expect_equal(cube[["file_info"]][[1]][["yres"]][[1]],
                 cube_local[["file_info"]][[1]][["yres"]][[1]])
    unlink(sapply(cube_local[["file_info"]], `[[`, "path"))

    cube_local_roi_tr <- sits_cube_copy(
        cube = cube,
        output_dir = tempdir(),
        roi = c(lon_min = -55.62248575,
                lat_min = -11.62017052,
                lon_max = -55.60154307,
                lat_max = -11.60790603),
        res = 464,
        multicores = 2
    )

    # Comparing bounding boxes
    bbox_roi_tr <- sits_bbox(cube_local_roi_tr, TRUE)
    expect_lt(bbox_tile[["xmin"]], bbox_roi_tr[["xmin"]])
    expect_lt(bbox_tile[["ymin"]], bbox_roi_tr[["ymin"]])
    expect_gt(bbox_tile[["xmax"]], bbox_roi_tr[["xmax"]])
    expect_gt(bbox_tile[["ymax"]], bbox_roi_tr[["ymax"]])
    # Comparing classes
    expect_equal(class(cube), class(cube_local_roi_tr))
    # Comparing timelines
    expect_equal(sits_timeline(cube), sits_timeline(cube_local_roi_tr))
    # Comparing X resolution
    expect_lt(cube[["file_info"]][[1]][["xres"]][[1]],
              cube_local_roi_tr[["file_info"]][[1]][["xres"]][[1]])
    # Comparing Y resolution
    expect_lt(cube[["file_info"]][[1]][["yres"]][[1]],
              cube_local_roi_tr[["file_info"]][[1]][["yres"]][[1]])
    expect_equal(cube_local_roi_tr[["file_info"]][[1]][["xres"]][[1]], 464)
    expect_equal(cube_local_roi_tr[["file_info"]][[1]][["yres"]][[1]], 464)
    unlink(sapply(cube_local_roi_tr[["file_info"]], `[[`, "path"))
})
