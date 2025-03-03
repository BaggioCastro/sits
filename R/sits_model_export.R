#' @title Export classification models
#' @name sits_model_export
#'
#' @author Rolf Simoes, \email{rolf.simoes@@inpe.br}
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description Given a trained machine learning or deep learning model,
#' exports the model as an object for further exploration outside the
#' "sits" package
#'
#' @param ml_model A trained machine learning model
#' @return An R object containing the model in the original format of
#' machine learning or deep learning package.
#' @export
sits_model_export <- function(ml_model){
    .check_is_sits_model(ml_model)
    # Dispatch
    UseMethod("sits_model_export", ml_model)
}
#' @rdname sits_model_export
#'
#' @export
sits_model_export.sits_model <- function(ml_model){
    .check_is_sits_model(ml_model)
    # Extract the result of the R RandomForest package
    model <- .ml_model(ml_model)
    return(model)
}
