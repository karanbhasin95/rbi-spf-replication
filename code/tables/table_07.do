version 19.0
clear all
set more off

* Table 7: Robustness of fitted moments to support choices.

local root ""
capture confirm file "data/baseline_data.dta"
if !_rc local root "`c(pwd)'"
if "`root'" == "" {
    capture confirm file "baseline_data.dta"
    if !_rc local root "`c(pwd)'/.."
}
if "`root'" == "" {
    capture confirm file "../data/baseline_data.dta"
    if !_rc local root "`c(pwd)'/.."
}
if "`root'" == "" {
    capture confirm file "../../data/baseline_data.dta"
    if !_rc local root "`c(pwd)'/../.."
}
if "`root'" == "" {
    display as error "Could not locate data/baseline_data.dta"
    exit 601
}
local shared_data "`root'/data/baseline_data.dta"
local output "`root'/results/tables/table07.csv"

capture mkdir "`root'/results"
capture mkdir "`root'/results/tables"

mata:
void table7_beta_objective(
    real scalar todo,
    real rowvector log_ab,
    real colvector z,
    real colvector target,
    real scalar value,
    real rowvector gradient,
    real matrix hessian)
{
    real scalar alpha, beta_p
    real colvector fitted

    alpha  = exp(log_ab[1])
    beta_p = exp(log_ab[2])
    fitted = ibeta(alpha, beta_p, z)
    value  = sum((fitted :- target):^2)
}

real rowvector table7_fit_beta(
    real colvector interior_edges,
    real colvector cumulative_target,
    real scalar support_lower,
    real scalar support_upper)
{
    transmorphic S
    real colvector z
    real rowvector starts, start, simplex_delta, best_p, candidate
    real scalar i, j, candidate_value, best_value
    real scalar alpha, beta_p, mean_value, variance_value
    real scalar lo, hi, mid, median_value

    z = (interior_edges :- support_lower) :/ ///
        (support_upper - support_lower)

    starts = (1, 2, 5, 10)
    best_value = .
    best_p = (., .)

    for (i = 1; i <= cols(starts); i++) {
        for (j = 1; j <= cols(starts); j++) {
            S = optimize_init()
            optimize_init_which(S, "min")
            optimize_init_evaluator(S, &table7_beta_objective())
            optimize_init_evaluatortype(S, "d0")
            optimize_init_argument(S, 1, z)
            optimize_init_argument(S, 2, cumulative_target)
            start = log((starts[i], starts[j]))
            optimize_init_params(S, start)
            optimize_init_technique(S, "nm")
            simplex_delta = .05 :* start
            if (simplex_delta[1] == 0) simplex_delta[1] = .00025
            if (simplex_delta[2] == 0) simplex_delta[2] = .00025
            optimize_init_nmsimplexdeltas(S, simplex_delta)
            optimize_init_conv_maxiter(S, 10000)
            optimize_init_conv_ptol(S, 1e-10)
            optimize_init_conv_vtol(S, 1e-10)
            optimize_init_tracelevel(S, "none")
            candidate = optimize(S)
            candidate_value = optimize_result_value(S)

            if (best_value == . | candidate_value < best_value) {
                best_value = candidate_value
                best_p = candidate
            }
        }
    }

    alpha  = exp(best_p[1])
    beta_p = exp(best_p[2])
    mean_value = support_lower + (support_upper - support_lower) * ///
        alpha / (alpha + beta_p)
    variance_value = (support_upper - support_lower)^2 * alpha * beta_p / ///
        ((alpha + beta_p)^2 * (alpha + beta_p + 1))

    lo = 0
    hi = 1
    for (i = 1; i <= 200; i++) {
        mid = (lo + hi) / 2
        if (ibeta(alpha, beta_p, mid) < .5) lo = mid
        else hi = mid
    }
    median_value = support_lower + (support_upper - support_lower) * ///
        ((lo + hi) / 2)

    return((mean_value, median_value, variance_value, alpha, beta_p, best_value))
}
end

use "`shared_data'", clear
keep if record_type == "sensitivity_histogram"
keep survey_round growth_bin_label growth_nowcast_probability ///
    growth_bin_midpoint
rename growth_bin_label growth
rename growth_nowcast_probability growth_nowcast
rename growth_bin_midpoint growth_cast
sort survey_round growth_cast
tempfile table7_bins
save "`table7_bins'"
quietly levelsof survey_round, local(survey_rounds)

tempfile rounds
tempname round_handle
postfile `round_handle' str8 survey_round byte has_open ///
    double baseline_mean baseline_median baseline_variance ///
    double narrow_mean narrow_median narrow_variance ///
    double wide_mean wide_median wide_variance ///
    double wider_mean wider_median wider_variance ///
    double midpoint_mean midpoint_median midpoint_variance ///
    using "`rounds'", replace

foreach sheet of local survey_rounds {
        use "`table7_bins'", clear
        keep if survey_round == "`sheet'"
        drop survey_round
        drop if missing(growth)
        replace growth_nowcast = 0 if missing(growth_nowcast)
        duplicates drop growth growth_nowcast growth_cast, force

        quietly summarize growth_nowcast, meanonly
        assert r(sum) > 0
        gen double probability = growth_nowcast / r(sum)

        gen byte open_lower = strpos(lower(growth), "below") > 0
        gen byte open_upper = strpos(lower(growth), "or more") > 0
        gen double first_number = .
        replace first_number = real(regexs(1)) if ///
            regexm(lower(growth), "([0-9]+[.]?[0-9]*)")
        gen double second_number = .
        replace second_number = real(regexs(1)) if ///
            regexm(lower(growth), "to[ ]+([0-9]+[.]?[0-9]*)")

        quietly count if open_lower | open_upper
        local has_open = r(N) > 0

        quietly summarize probability, meanonly
        assert abs(r(sum) - 1) < 1e-8

        gen double midpoint_component = probability * growth_cast
        quietly summarize midpoint_component, meanonly
        local midpoint_mean = r(sum)

        sort growth_cast
        gen double midpoint_cumulative = sum(probability)
        quietly summarize growth_cast if midpoint_cumulative >= .5, meanonly
        local midpoint_median = r(min)

        gen double midpoint_variance_component = ///
            probability * (growth_cast - `midpoint_mean')^2
        quietly summarize midpoint_variance_component, meanonly
        local midpoint_variance = r(sum)

        tempfile bins
        save "`bins'"

        foreach scenario in baseline narrow wide wider {
            use "`bins'", clear

            if "`scenario'" == "baseline" {
                local fixed_lower = 2
                local fixed_upper = 13
            }
            else if "`scenario'" == "narrow" {
                local fixed_lower = 2.5
                local fixed_upper = 12
            }
            else if "`scenario'" == "wide" {
                local fixed_lower = 1
                local fixed_upper = 14
            }
            else if "`scenario'" == "wider" {
                local fixed_lower = 0
                local fixed_upper = 15
            }

            gen double bin_lower = first_number
            gen double bin_upper = second_number
            replace bin_lower = `fixed_lower' if open_lower
            replace bin_upper = first_number if open_lower
            replace bin_upper = `fixed_upper' if open_upper

            assert !missing(bin_lower, bin_upper, probability)
            sort bin_lower
            gen double cumulative_target = sum(probability)
            gen double interior_edge = bin_upper

            local support_lower = bin_lower[1]
            local support_upper = bin_upper[_N]
            local n_interior = _N - 1

            mata: st_matrix("table7_fit", table7_fit_beta( ///
                st_data((1::`n_interior'), "interior_edge"), ///
                st_data((1::`n_interior'), "cumulative_target"), ///
                `support_lower', `support_upper'))

            local `scenario'_mean = el(table7_fit, 1, 1)
            local `scenario'_median = el(table7_fit, 1, 2)
            local `scenario'_variance = el(table7_fit, 1, 3)
        }

        post `round_handle' ("`sheet'") (`has_open') ///
            (`baseline_mean') (`baseline_median') (`baseline_variance') ///
            (`narrow_mean') (`narrow_median') (`narrow_variance') ///
            (`wide_mean') (`wide_median') (`wide_variance') ///
            (`wider_mean') (`wider_median') (`wider_variance') ///
            (`midpoint_mean') (`midpoint_median') (`midpoint_variance')
}
postclose `round_handle'

use "`rounds'", clear
sort survey_round

tempfile computed
tempname summary_handle
postfile `summary_handle' str32 method ///
    double average_mean average_median average_variance ///
    variance_correlation_with_baseli ///
    max_abs_mean_difference max_abs_median_difference ///
    max_abs_variance_difference using "`computed'", replace

foreach scenario in baseline narrow wide wider midpoint {
    quietly summarize `scenario'_mean, meanonly
    local average_mean = r(mean)
    quietly summarize `scenario'_median, meanonly
    local average_median = r(mean)
    quietly summarize `scenario'_variance, meanonly
    local average_variance = r(mean)

    if "`scenario'" == "baseline" {
        local method "Beta: Baseline [2,13]"
        local variance_correlation = .
        local max_mean_difference = .
        local max_median_difference = .
        local max_variance_difference = .
    }
    else {
        quietly correlate baseline_variance `scenario'_variance
        matrix table7_corr = r(C)
        local variance_correlation = el(table7_corr, 1, 2)

        gen double difference = abs(baseline_mean - `scenario'_mean)
        quietly summarize difference, meanonly
        local max_mean_difference = r(max)
        drop difference

        gen double difference = abs(baseline_median - `scenario'_median)
        quietly summarize difference, meanonly
        local max_median_difference = r(max)
        drop difference

        gen double difference = abs(baseline_variance - `scenario'_variance)
        quietly summarize difference, meanonly
        local max_variance_difference = r(max)
        drop difference

        if "`scenario'" == "narrow" local method "Beta: Narrow [2.5,12]"
        if "`scenario'" == "wide" local method "Beta: Wide [1,14]"
        if "`scenario'" == "wider" local method "Beta: Wider [0,15]"
        if "`scenario'" == "midpoint" local method "Discrete midpoint"
    }

    post `summary_handle' ("`method'") ///
        (`average_mean') (`average_median') (`average_variance') ///
        (`variance_correlation') (`max_mean_difference') ///
        (`max_median_difference') (`max_variance_difference')
}
postclose `summary_handle'

use "`computed'", clear
export delimited using "`output'", replace
save "`computed'", replace

* Compare every nonmissing printed value with the independently computed result.
clear
input str32 method double(rep_avg_mean rep_avg_median rep_avg_variance ///
    rep_var_corr rep_max_mean_diff rep_max_median_diff rep_max_variance_diff)
"Beta: Baseline [2,13]"   6.6898 6.6898 .2576 .      .      .      .
"Beta: Narrow [2.5,12]"  6.6889 6.6903 .2578 .9999  .0113  .0051  .0124
"Beta: Wide [1,14]"      6.6899 6.6899 .2576 1      .0070  .0031  .0080
"Beta: Wider [0,15]"     6.6900 6.6899 .2575 .9999  .0118  .0051  .0135
"Discrete midpoint"      6.7311 6.7345 .5159 .9300  .1044  .2873 1.0789
end

merge 1:1 method using "`computed'", assert(match) nogen

rename average_mean calc_avg_mean
rename average_median calc_avg_median
rename average_variance calc_avg_variance
rename variance_correlation_with_baseli calc_var_corr
rename max_abs_mean_difference calc_max_mean_diff
rename max_abs_median_difference calc_max_median_diff
rename max_abs_variance_difference calc_max_variance_diff

reshape long rep_ calc_, i(method) j(metric) string
drop if missing(rep_)
rename rep_ reported_value
rename calc_ computed_value
gen double difference = computed_value - reported_value
gen byte matches_at_4_decimals = round(computed_value, .0001) == ///
    round(reported_value, .0001)
order method metric reported_value computed_value difference matches_at_4_decimals
sort method metric

count
display as result "TABLE_07_VALUES_CHECKED=" r(N)
count if matches_at_4_decimals
display as result "TABLE_07_VALUES_MATCHED=" r(N)
count if !matches_at_4_decimals
display as result "TABLE_07_VALUES_DIFFERENT=" r(N)
