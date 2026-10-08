version 19.0
clear all
set more off
args diagnosticfile

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
keep if record_type == "figure09_density_fit"
keep density_date qdate density_bin_label density_bin_midpoint density_weight
assert _N == 753
isid density_date density_bin_label

bysort density_date: egen double density_total = total(density_weight)
bysort density_date: egen long fitted_bin_count = count(density_weight)
gen double density_probability = density_weight/density_total
gen double weighted_level = density_probability*density_bin_midpoint
bysort density_date: egen double density_mean = total(weighted_level)
replace density_mean = . if fitted_bin_count == 0
gen double weighted_variance = ///
    density_probability*(density_bin_midpoint-density_mean)^2
bysort density_date: egen double density_variance = total(weighted_variance)
gen double density_sd = sqrt(density_variance)
replace density_sd = . if fitted_bin_count == 0
gen double weighted_skewness = density_probability * ///
    ((density_bin_midpoint-density_mean)/density_sd)^3
bysort density_date: egen double density_skewness = total(weighted_skewness)
replace density_skewness = . if fitted_bin_count == 0 | ///
    missing(density_sd) | density_sd <= 0

collapse (mean) density_skewness density_mean density_sd ///
    (first) qdate, by(density_date)
collapse (mean) density_skewness density_mean density_sd, by(qdate)
sort qdate
assert _N == 62
assert qdate[1] == tq(2007q4)
assert qdate[_N] == tq(2023q1)


count if missing(density_skewness)
assert r(N) == 1
assert missing(density_skewness) if qdate == tq(2013q1)
replace density_skewness = density_skewness[_n-1] ///
    if qdate == tq(2013q1) & missing(density_skewness)
assert !missing(density_skewness)
keep if inrange(qdate, tq(2008q1), tq(2023q1))
assert _N == 61
summarize density_skewness if qdate == tq(2008q1), meanonly
tempname skewness_base
scalar `skewness_base' = r(mean)
assert `skewness_base' < 0
gen double skewness = density_skewness / `skewness_base'
rename density_skewness yearahead_skewness
keep qdate skewness yearahead_skewness
tempfile quarterly_skewness
save "`quarterly_skewness'", replace


use "`data'", clear
keep if record_type == "fitted_growth"
keep qdate growth_uncertainty
collapse (mean) growth_uncertainty, by(qdate)
keep if inrange(qdate, tq(2008q1), tq(2023q1))
assert _N == 61
assert !missing(growth_uncertainty)
summarize growth_uncertainty if qdate == tq(2008q1), meanonly
tempname uncertainty_base
scalar `uncertainty_base' = r(mean)
assert `uncertainty_base' > 0 & !missing(`uncertainty_base')
gen double spf_uncertainty = growth_uncertainty / `uncertainty_base'
merge 1:1 qdate using "`quarterly_skewness'", assert(3) nogen
sort qdate


gen double recession_source_quarter = qdate - 2
gen byte recession = ///
    inrange(recession_source_quarter, tq(2008q2), tq(2008q3)) | ///
    inrange(recession_source_quarter, tq(2013q1), tq(2013q2)) | ///
    recession_source_quarter == tq(2016q3) | ///
    inrange(recession_source_quarter, tq(2019q4), tq(2020q4))
count if recession
assert r(N) == 10

order qdate spf_uncertainty skewness growth_uncertainty yearahead_skewness recession
if "`diagnosticfile'" != "" {
    export delimited using "`diagnosticfile'", replace
}

gen double recession_lower = -4 if recession
gen double recession_upper = 5 if recession
twoway (rbar recession_lower recession_upper qdate if recession, ///
            color(gs12) lcolor(none) barwidth(1)) ///
       (line spf_uncertainty qdate, lcolor(navy) lwidth(medthick)) ///
       (line skewness qdate, lcolor(gs8) lpattern(dash) lwidth(medthick)), ///
       title("Nowcast Growth Density: Skewness and Uncertainty") ///
       yline(0, lcolor(gs12)) xtitle("") ytitle("") ///
       xlabel(`=tq(2008q1)'(2)`=tq(2023q1)', format(%tq) angle(45)) ///
       ylabel(-4(1)5, angle(horizontal)) ///
       graphregion(color(white)) plotregion(color(white)) ///
       legend(order(1 "Recession" 2 "SPF Uncertainty" 3 "Skewness") rows(1))
graph export "`out'/appendix_figure_d1.png", replace width(2200)
