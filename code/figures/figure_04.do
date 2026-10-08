version 19.0
clear all
set more off
* Locate the package root when run from the root, data/, code/,
* code/tables/, or code/figures/. No machine-specific path is required.
local root ""
foreach candidate in "`c(pwd)'" "`c(pwd)'/.." "`c(pwd)'/../.." {
    if "`root'" == "" {
        capture confirm file "`candidate'/data/baseline_data.dta"
        if !_rc {
            capture confirm file "`candidate'/code/master.do"
            if !_rc local root "`candidate'"
        }
    }
}
if "`root'" == "" {
    display as error "Could not locate the replication package's data/baseline_data.dta."
    display as error "Change directory to the package folder containing code/ and data/, then rerun the whole do-file."
    exit 601
}
local data "`root'/data/baseline_data.dta"
local out "`root'/results/figures"
capture mkdir "`root'/results"
capture mkdir "`out'"
set scheme s2color
graph set window fontface "Times New Roman"

use "`data'", clear
keep if record_type == "spf_histogram"
keep survey_date survey_year survey_month growth_bin_midpoint ///
    growth_nowcast_probability growth_yearahead_probability

gen double nowcast_component = ///
    growth_bin_midpoint * growth_nowcast_probability
gen double yearahead_component = ///
    growth_bin_midpoint * growth_yearahead_probability
collapse (sum) nowcast_component yearahead_component ///
    growth_nowcast_probability growth_yearahead_probability, ///
    by(survey_date survey_year survey_month)

gen double nowcast_mean = nowcast_component
replace nowcast_mean = . if growth_nowcast_probability == 0
gen double yearahead_mean = yearahead_component
replace yearahead_mean = . if growth_yearahead_probability == 0
assert !missing(nowcast_mean)


sort survey_date
count if missing(yearahead_mean)
assert r(N) == 1
replace yearahead_mean = (yearahead_mean[_n-1] + yearahead_mean[_n+1]) / 2 ///
    if missing(yearahead_mean) & !missing(yearahead_mean[_n-1], yearahead_mean[_n+1])
assert !missing(yearahead_mean)

gen byte selected_round = inlist(survey_month, 3, 5, 6, 9, 11, 12)
replace selected_round = 1 if inlist(survey_date, ///
    td(30apr2011), td(30jul2011), td(28jan2023))
keep if selected_round & inrange(survey_date, td(30jun2008), td(28jan2023))

gen int base_year = survey_year - (survey_month <= 3)
bysort base_year (survey_date): gen byte release_order = _n
by base_year: assert _N == 4
assert inrange(base_year, 2008, 2022)

tempfile nowcast_path forecast_path
preserve
    gen int year = base_year
    gen byte horizon = 5 - release_order
    gen double mean_growth_forecast = nowcast_mean

    replace mean_growth_forecast = yearahead_mean if base_year == 2022
    keep year horizon mean_growth_forecast
    save "`nowcast_path'", replace
restore

gen int year = base_year + 1
gen byte horizon = 9 - release_order
gen double mean_growth_forecast = yearahead_mean
keep year horizon mean_growth_forecast
append using "`nowcast_path'"
keep if inrange(year, 2009, 2022)
assert _N == 112
assert inrange(horizon, 1, 8)
assert !missing(mean_growth_forecast)
isid year horizon
save "`forecast_path'", replace

use "`data'", clear
keep if record_type == "annual_gdp"
keep annual_year annual_real_gdp
sort annual_year
tsset annual_year
gen double actual_growth = 100 * (annual_real_gdp / L.annual_real_gdp - 1)
keep if inrange(annual_year, 2009, 2022)
rename annual_year year
gen byte horizon = 0
rename actual_growth mean_growth_forecast
keep year horizon mean_growth_forecast
append using "`forecast_path'"

gen byte path_order = cond(horizon == 0, 9, 9 - horizon)
gen str6 horizon_label = cond(horizon == 0, "Actual", ///
    "H" + string(horizon, "%1.0f"))
sort year path_order
assert _N == 126
assert !missing(year, horizon, path_order, mean_growth_forecast)
isid year path_order

bysort year: egen double actual = max(cond(horizon == 0, mean_growth_forecast, .))
assert !missing(actual)
drop if horizon == 0
rename mean_growth_forecast forecast
gen byte target_id = 1
keep year target_id horizon forecast actual
assert _N == 112
assert inrange(horizon, 1, 8)
isid target_id year horizon

tempfile gdp_errors
save "`gdp_errors'", replace

use "`data'", clear
keep if record_type == "figure_04_infl_error"
keep annual_year figure_error_horizon figure_forecast_value figure_actual_value
rename annual_year year
rename figure_error_horizon horizon
rename figure_forecast_value forecast
rename figure_actual_value actual
gen byte target_id = 2
assert _N == 60
assert inrange(horizon, 1, 4)
isid target_id year horizon

append using "`gdp_errors'"
assert _N == 172
assert !missing(target_id, year, horizon, forecast, actual)
isid target_id year horizon

gen double absolute_error = abs(forecast - actual)
collapse (mean) mae=absolute_error (count) sample_n=absolute_error, by(target_id horizon)
assert sample_n == 14 if target_id == 1
assert sample_n == 15 if target_id == 2
reshape wide mae sample_n, i(horizon) j(target_id)
rename mae1 gdp_mae
rename mae2 inflation_mae
assert _N == 8

gen byte plot_order = 9-horizon
label define horizon_order 1 "H8" 2 "H7" 3 "H6" 4 "H5" ///
    5 "H4" 6 "H3" 7 "H2" 8 "H1"
label values plot_order horizon_order
sort plot_order

graph bar (asis) gdp_mae inflation_mae, over(plot_order, label(angle(horizontal))) ///
    bar(1, color("0 32 96") lcolor("0 32 96")) ///
    bar(2, color(gs12) lcolor(gs8)) ///
    title("Mean Absolute Forecast Error", size(medlarge)) ///
    yscale(range(0 3)) ylabel(0(1)3, angle(horizontal) grid glcolor(gs14) glpattern(dot)) ///
    ytitle("") legend(order(1 "GDP Growth Rate" 2 "Inflation") rows(1) ///
        position(6) ring(1) region(lstyle(none) fcolor(none))) ///
    graphregion(color(white)) plotregion(color(white)) ///
    xsize(11) ysize(5)
graph export "`out'/figure04.png", replace width(2200)
