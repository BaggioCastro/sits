test_that("Combine predictions", {
    # create a data cube from local files
    data_dir <- system.file("extdata/raster/mod13q1", package = "sits")
    cube <- sits_cube(
        source = "BDC",
        collection = "MOD13Q1-6",
        data_dir = data_dir,
        delim = "_",
        parse_info = c("X1", "tile", "band", "date")
    )
    # create a random forest model
    rfor_model <- sits_train(samples_modis_ndvi, sits_rfor())
    # classify a data cube using rfor model
    probs_rfor_cube <- sits_classify(
        data = cube, ml_model = rfor_model,
        output_dir = tempdir(),
        version = "rfor"
    )
    # create an XGBoost model
    xgb_model <- sits_train(samples_modis_ndvi, sits_xgboost())
    # classify a data cube using xgboost model
    probs_xgb_cube <- sits_classify(
        data = cube, ml_model = xgb_model,
        output_dir = tempdir(),
        version = "xgb"
    )
    # create a list of predictions to be combined
    pred_cubes <- list(probs_rfor_cube, probs_xgb_cube)
    # combine predictions
    comb_probs_cube_avg <- sits_combine_predictions(
        cubes = pred_cubes,
        type = "average",
        output_dir = tempdir(),
        version = "comb_rfor_xgb_avg"
    )
    expect_equal(sits_labels(comb_probs_cube_avg), sits_labels(probs_xgb_cube))
    expect_equal(sits_bbox(comb_probs_cube_avg), sits_bbox(probs_xgb_cube))
    expect_equal(nrow(comb_probs_cube_avg), nrow(probs_xgb_cube))
    # Resume feature
    comb_probs_cube_avg <- sits_combine_predictions(
        cubes = pred_cubes,
        type = "average",
        output_dir = tempdir(),
        version = "comb_rfor_xgb_avg"
    )

    # combine predictions
    uncert_rfor <- sits_uncertainty(
        cube = probs_rfor_cube,
        output_dir = tempdir()
    )
    uncert_xgboost <- sits_uncertainty(
        cube = probs_xgb_cube,
        output_dir = tempdir()
    )
    uncert_cubes <- list(uncert_rfor, uncert_xgboost)

    comb_probs_cube_uncert <- sits_combine_predictions(
        cubes = pred_cubes,
        type = "uncertainty",
        uncert_cubes = uncert_cubes,
        output_dir = tempdir(),
        version = "comb_rfor_xgb_uncert"
    )
    expect_equal(sits_labels(comb_probs_cube_uncert), sits_labels(probs_xgb_cube))
    expect_equal(sits_bbox(comb_probs_cube_uncert), sits_bbox(probs_xgb_cube))
    expect_equal(nrow(comb_probs_cube_uncert), nrow(probs_xgb_cube))
    # Resume feature
    comb_probs_cube_uncert <- sits_combine_predictions(
        cubes = pred_cubes,
        type = "uncertainty",
        uncert_cubes = uncert_cubes,
        output_dir = tempdir(),
        version = "comb_rfor_xgb_uncert"
    )
})
