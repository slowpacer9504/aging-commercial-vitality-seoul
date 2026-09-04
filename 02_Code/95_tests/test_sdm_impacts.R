#==============================================================================
# Script    : test_sdm_impacts.R
# Purpose   : Regression tests for compute_true_sdm_effects(), which produces the
#             direct / indirect / total effects reported as the SPDM main result.
# Type      : qc
# Inputs    : utils_spdm.R; optionally 03_Output/01_Tables/spdm_*.csv
#==============================================================================

test_context("compute_true_sdm_effects(): LeSage-Pace matrix impacts")

# Row-standardised queen-style W on 5 units in a line. Zero diagonal, rows sum
# to 1, which is the contract every W in this project satisfies.
make_row_std_W <- function(n = 5L) {
  W <- matrix(0, n, n)
  for (i in seq_len(n)) {
    nb <- c(i - 1L, i + 1L)
    nb <- nb[nb >= 1L & nb <= n]
    W[i, nb] <- 1
  }
  W / rowSums(W)
}

W <- make_row_std_W(5L)

expect_equal_num(rowSums(W), rep(1, 5), "test fixture W is row-standardised")
expect_equal_num(diag(W), rep(0, 5), "test fixture W has zero diagonal")

# --- 1. No spatial structure at all reduces to OLS ---------------------------
eff <- compute_true_sdm_effects(W, rho = 0, beta = 0.75, theta = 0)
expect_equal_num(eff[["direct"]], 0.75, "rho=0, theta=0 -> direct equals beta")
expect_equal_num(eff[["indirect"]], 0, "rho=0, theta=0 -> indirect is zero")
expect_equal_num(eff[["total"]], 0.75, "rho=0, theta=0 -> total equals beta")

# --- 2. SLX case: no endogenous feedback, spillover is exactly theta ---------
eff <- compute_true_sdm_effects(W, rho = 0, beta = 0.75, theta = -0.30)
expect_equal_num(eff[["direct"]], 0.75, "rho=0 -> direct equals beta (W has zero diagonal)")
expect_equal_num(eff[["indirect"]], -0.30, "rho=0 -> indirect equals theta")
expect_equal_num(eff[["total"]], 0.45, "rho=0 -> total equals beta + theta")

# --- 3. The row-standardised total identity ---------------------------------
# For any row-standardised W, S %*% 1 = 1/(1-rho), so
#   total = mean(rowSums(S(beta I + theta W))) = (beta + theta) / (1 - rho)
# exactly. This is the strongest closed-form check available on the function and
# it holds for every W the project uses.
for (params in list(
  c(rho = 0.25, beta = 1.0, theta = 0.0),
  c(rho = -0.40, beta = -0.5, theta = 0.9),
  c(rho = 0.60, beta = 0.2, theta = -1.3),
  c(rho = 0.0219208460, beta = 0.5783715830, theta = -2.1182104590)
)) {
  eff <- compute_true_sdm_effects(W, rho = params[["rho"]], beta = params[["beta"]], theta = params[["theta"]])
  expect_equal_num(
    eff[["total"]],
    (params[["beta"]] + params[["theta"]]) / (1 - params[["rho"]]),
    sprintf("total = (beta+theta)/(1-rho) at rho=%.4f", params[["rho"]])
  )
}

# --- 4. Decomposition is internally consistent -------------------------------
eff <- compute_true_sdm_effects(W, rho = 0.35, beta = 0.8, theta = -0.2)
expect_equal_num(eff[["direct"]] + eff[["indirect"]], eff[["total"]],
                 "direct + indirect = total")

# --- 5. Positive rho creates feedback that raises the own-unit effect --------
base_beta <- 0.5
eff_no_fb <- compute_true_sdm_effects(W, rho = 0, beta = base_beta, theta = 0)
eff_fb <- compute_true_sdm_effects(W, rho = 0.5, beta = base_beta, theta = 0)
expect_true(eff_fb[["direct"]] > eff_no_fb[["direct"]],
            "rho>0 adds feedback so direct exceeds beta")
expect_true(eff_fb[["indirect"]] > 0,
            "rho>0 with theta=0 still produces positive indirect effects")

# --- 6. Sign convention: a negative exposure effect stays negative -----------
eff <- compute_true_sdm_effects(W, rho = 0.17, beta = -0.95, theta = 0.02)
expect_true(eff[["direct"]] < 0, "negative beta yields negative direct effect")


#==============================================================================
# Regression against the published SPDM output
#==============================================================================

test_context("compute_true_sdm_effects(): published spdm_impacts.csv consistency")

impacts_path <- cfg$paths$spdm_impacts
models_path <- cfg$paths$spdm_main_models

if (!file.exists(impacts_path) || !file.exists(models_path)) {
  test_skip("published impacts satisfy the row-standardised identity",
            "spdm_impacts.csv or spdm_main_models.csv not present")
} else {
  imp <- utils::read.csv(impacts_path, stringsAsFactors = FALSE)
  mods <- utils::read.csv(models_path, stringsAsFactors = FALSE)
  imp <- imp[imp$status == "success", , drop = FALSE]

  # splm names the spatial autoregressive parameter of a lag model "lambda";
  # utils_spdm.R reads it as rho. If that mapping ever breaks, the identity below
  # stops holding, which is exactly what this test is here to catch.
  checked <- 0L
  bad <- character(0)
  for (i in seq_len(nrow(imp))) {
    oc <- imp$outcome[[i]]
    rho <- mods$estimate[mods$outcome == oc & mods$term == "lambda"]
    beta <- mods$estimate[mods$outcome == oc & mods$term == imp$focal_var[[i]]]
    theta <- mods$estimate[mods$outcome == oc & mods$term == paste0("w_", imp$focal_var[[i]])]
    if (length(rho) != 1L || length(beta) != 1L || length(theta) != 1L) next
    expected_total <- (beta + theta) / (1 - rho)
    checked <- checked + 1L
    if (!isTRUE(abs(imp$total[[i]] - expected_total) < 1e-6)) {
      bad <- c(bad, sprintf("%s: published=%.10f identity=%.10f", oc, imp$total[[i]], expected_total))
    }
  }

  expect_true(checked > 0L, "published impact rows were matched to coefficients")
  expect_true(length(bad) == 0L,
              sprintf("all %d published totals satisfy (beta+theta)/(1-rho)", checked))
  if (length(bad) > 0L) cat(sprintf("        %s\n", bad), sep = "")

  # indirect = total - direct must hold in the published table as well.
  resid <- abs((imp$direct + imp$indirect) - imp$total)
  expect_true(all(resid < 1e-9, na.rm = TRUE),
              "published direct + indirect = total for every row")
}
