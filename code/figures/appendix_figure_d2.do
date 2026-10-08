version 19.0
clear all
set more off


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
local irf_file "`root'/.appendix_figure_d2_runtime"
global REPRO_FIG_OUT "`out'"
capture mkdir "`root'/results"
capture mkdir "`out'"
set scheme s2color
graph set window fontface "Times New Roman"

program define plot_appendix_d2_irf
    syntax, Response(string) File(string) Title(string)
    twoway (line coirf horizon if response=="`response'", ///
                lcolor(gs8) lpattern(dash) lwidth(thick)), ///
           title("`title'") xlabel(0(1)10) xtitle("") ytitle("") ///
           yline(0, lcolor(gs12)) ///
           legend(order(1 "SVAR (7) Skewness Shock") rows(1))
    graph export "$REPRO_FIG_OUT/`file'", replace width(1800)
end


use "`data'", clear
keep if record_type == "growth_density_fit"
keep density_date qdate density_bin_label density_bin_midpoint density_weight
assert _N == 652
isid density_date density_bin_label
bysort density_date: egen double density_total = total(density_weight)
gen double density_probability = density_weight/density_total
gen double weighted_level = density_probability*density_bin_midpoint
bysort density_date: egen double density_mean = total(weighted_level)
gen double weighted_variance = ///
    density_probability*(density_bin_midpoint-density_mean)^2
bysort density_date: egen double density_variance = total(weighted_variance)
gen double density_sd = sqrt(density_variance)
gen double weighted_skewness = density_probability * ///
    ((density_bin_midpoint-density_mean)/density_sd)^3
bysort density_date: egen double skew_growth_ncast = total(weighted_skewness)
collapse (mean) skew_growth_ncast, by(density_date qdate)
collapse (mean) skew_growth_ncast, by(qdate)
assert _N == 62
tempfile quarterly_skewness
save "`quarterly_skewness'", replace


use "`data'", clear
keep if record_type == "svar_model_input"
keep qdate svar_real_gdp svar_real_gfcf svar_cpi ///
    svar_spf_uncertainty svar_policy_rate svar_exchange_rate
isid qdate
merge 1:1 qdate using "`quarterly_skewness'", nogen
sort qdate
assert _N == 68

gen double yr_gdp = 100*ln(svar_real_gdp/svar_real_gdp[_n-4])
gen double yr_gfcf = 100*ln(svar_real_gfcf/svar_real_gfcf[_n-4])
gen double ycpi = 100*ln(svar_cpi/svar_cpi[_n-4])
gen double ysd_beta_fit_growth_ncast = ///
    100*ln(svar_spf_uncertainty/svar_spf_uncertainty[_n-1])
gen double ypolicy_rate = ///
    100*ln(svar_policy_rate/svar_policy_rate[_n-1])
gen double yexchange_rate = ///
    100*ln(svar_exchange_rate/svar_exchange_rate[_n-1])
tsset qdate, quarterly
gen double d_skew_growth_ncast = D.skew_growth_ncast

matrix A7 = (1,0,0,0,0,0,0\.,1,0,0,0,0,0\.,.,1,0,0,0,0\ ///
    .,.,.,1,0,0,0\.,.,.,.,1,0,0\.,.,.,.,.,1,0\.,.,.,.,.,.,1)
matrix B7 = (.,0,0,0,0,0,0\0,.,0,0,0,0,0\0,0,.,0,0,0,0\ ///
    0,0,0,.,0,0,0\0,0,0,0,.,0,0\0,0,0,0,0,.,0\0,0,0,0,0,0,.)

irf set "`irf_file'", replace
quietly svar yr_gdp yr_gfcf ycpi ysd_beta_fit_growth_ncast ///
    d_skew_growth_ncast ypolicy_rate yexchange_rate, ///
    lags(1/1) aeq(A7) beq(B7)
display as result "APPENDIX_D2_SVAR7_N=" e(N)
irf create skew_7var, step(10) replace

use "`irf_file'.irf", clear
keep if irfname == "skew_7var" & impulse == "d_skew_growth_ncast"
keep if inlist(response, "yr_gdp", "yr_gfcf", "ycpi", ///
    "ypolicy_rate", "yexchange_rate")
keep step response coirf
rename step horizon
replace response = "GDP" if response == "yr_gdp"
replace response = "GFCF" if response == "yr_gfcf"
replace response = "Inflation" if response == "ycpi"
replace response = "Policy Rate" if response == "ypolicy_rate"
replace response = "USD-INR Exchange Rate" if response == "yexchange_rate"
gen str32 model = "SVAR (7) Skewness Shock"
assert _N == 55
isid response horizon
assert inrange(horizon, 0, 10)
assert !missing(coirf)
sort response horizon

plot_appendix_d2_irf, response("GDP") file("appendix_figure_d2a.png") ///
    title("Cumulative Effect of 1 s.d. Skewness Shock on GDP")
plot_appendix_d2_irf, response("GFCF") file("appendix_figure_d2b.png") ///
    title("Cumulative Effect of 1 s.d. Skewness Shock on GFCF")
plot_appendix_d2_irf, response("Inflation") file("appendix_figure_d2c.png") ///
    title("Cumulative Effect of 1 s.d. Skewness Shock on Inflation")
plot_appendix_d2_irf, response("Policy Rate") file("appendix_figure_d2d.png") ///
    title("Cumulative Effect of 1 s.d. Skewness Shock on Policy Rate")
plot_appendix_d2_irf, response("USD-INR Exchange Rate") file("appendix_figure_d2e.png") ///
    title("Cumulative Effect of 1 s.d. Skewness Shock on Exchange Rate")
capture erase "`irf_file'.irf"
