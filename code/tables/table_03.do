version 19.0
clear all
set more off

* Locate the replication root from common starting directories.
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
local data "`root'/data/baseline_data.dta"
local output "`root'/results/tables/table03.csv"
capture mkdir "`root'/results"
capture mkdir "`root'/results/tables"

tempfile assigned actual


use "`data'", clear
keep if record_type == "spf_histogram"
keep survey_quarter growth_bin_midpoint growth_nowcast_probability ///
    growth_yearahead_probability
drop if missing(growth_bin_midpoint)

gen byte interval_id = 1 if growth_bin_midpoint < 4
replace interval_id = 2 if inrange(growth_bin_midpoint, 4, 5.999999)
replace interval_id = 3 if inrange(growth_bin_midpoint, 6, 7.999999)
replace interval_id = 4 if inrange(growth_bin_midpoint, 8, 9.999999)
replace interval_id = 5 if growth_bin_midpoint >= 10
drop if missing(interval_id)

gen double nowcast_component = growth_nowcast_probability
gen double yearahead_component = growth_yearahead_probability
replace nowcast_component = 0 if missing(nowcast_component)
replace yearahead_component = 0 if missing(yearahead_component)


replace nowcast_component = nowcast_component / 10 ///
    if survey_quarter == 1 & interval_id == 1

collapse (sum) nowcast_component yearahead_component, ///
    by(survey_quarter interval_id)
gen double assigned_probability = nowcast_component + yearahead_component
gen byte published_interval_id = cond(interval_id >= 4, 4, interval_id)
collapse (sum) assigned_probability, by(published_interval_id)
rename published_interval_id interval_id
save "`assigned'", replace


use "`data'", clear
keep if record_type == "annual_gdp"
keep annual_year annual_real_gdp
sort annual_year
gen double growth_actual = 100 * (annual_real_gdp / annual_real_gdp[_n-1] - 1)
keep if inrange(annual_year, 2007, 2022)
replace growth_actual = round(growth_actual, .01)
gen byte interval_id = 1 if growth_actual < 4
replace interval_id = 2 if inrange(growth_actual, 4, 5.999999)
replace interval_id = 3 if inrange(growth_actual, 6, 7.999999)
replace interval_id = 4 if growth_actual >= 8
contract interval_id, freq(outcome_count)
quietly summarize outcome_count, meanonly
assert r(sum) == 16
save "`actual'", replace

use "`assigned'", clear
merge 1:1 interval_id using "`actual'", assert(match) nogen
egen double assigned_total = total(assigned_probability)
egen double outcome_total = total(outcome_count)
gen double actual_occurrence = outcome_count * assigned_total / outcome_total
gen double relative_probability = assigned_probability / assigned_total
gen double relative_occurrence = outcome_count / outcome_total
gen double variance_weight = relative_occurrence * (1 - relative_occurrence)
gen double standardized_difference = ///
    (relative_probability - relative_occurrence) / sqrt(variance_weight)
gen double chi_square_unscaled = standardized_difference^2


gen double documented_scaling_factor = 12.8
gen double chi_square_scaled = chi_square_unscaled * documented_scaling_factor
gen str24 interval = ""
replace interval = "Below 4 per cent" if interval_id == 1
replace interval = "4 - 6 per cent" if interval_id == 2
replace interval = "6 - 8 per cent" if interval_id == 3
replace interval = "Above 8 per cent" if interval_id == 4
gen str12 table = "Growth"

foreach variable in assigned_probability actual_occurrence outcome_count ///
    chi_square_unscaled chi_square_scaled {
    quietly summarize `variable', meanonly
    local sum_`variable' = r(sum)
}
set obs `=_N+1'
replace interval = "Overall" in L
replace table = "Growth" in L
replace assigned_probability = `sum_assigned_probability' in L
replace actual_occurrence = `sum_actual_occurrence' in L
replace outcome_count = `sum_outcome_count' in L
replace chi_square_unscaled = `sum_chi_square_unscaled' in L
replace documented_scaling_factor = 12.8 in L
replace chi_square_scaled = `sum_chi_square_scaled' in L
sort interval_id
order table interval assigned_probability actual_occurrence outcome_count ///
    relative_probability relative_occurrence variance_weight ///
    standardized_difference chi_square_unscaled ///
    documented_scaling_factor chi_square_scaled
drop interval_id assigned_total outcome_total
export delimited using "`output'", replace
