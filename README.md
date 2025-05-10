# tracker-collection

This is my personal collection of BASH-only Telegram trackers hosted completely serverlessly on GitHub Actions.

## Tracker List
This lists all trackers hosted within this repository.  
Click on the tracker name to get more information.
* [GitHub DMCA Tracker](github/dmca/)
* [LineageOS Devices Tracker](lineageos/devices/)
* [Phone Release Radar](gsmarena/release/)
* [LineageLeaks](lineageos/leaks/)
* [GitHub Releases Tracker](github/releases)
* [ReVanced Releases Tracker](github/releases/README-revanced.md)
* [Magisk Modules Tracker](magisk/modules/)

## Tracker Status
[![GitHub DMCA Tracker](https://github.com/programminghoch10/tracker-collection/actions/workflows/github-dmca.yml/badge.svg)](https://github.com/programminghoch10/tracker-collection/actions/workflows/github-dmca.yml)  
[![LineageOS Devices Tracker Nightly](https://github.com/programminghoch10/tracker-collection/actions/workflows/lineageos-devices-nightly.yml/badge.svg)](https://github.com/programminghoch10/tracker-collection/actions/workflows/lineageos-devices-nightly.yml)  
[![LineageOS Devices Tracker Nightly](https://github.com/programminghoch10/tracker-collection/actions/workflows/lineageos-devices-fullcheck.yml/badge.svg)](https://github.com/programminghoch10/tracker-collection/actions/workflows/lineageos-devices-fullcheck.yml)  
[![GSMArena Releases Tracker](https://github.com/programminghoch10/tracker-collection/actions/workflows/gsmarena-release.yml/badge.svg)](https://github.com/programminghoch10/tracker-collection/actions/workflows/gsmarena-release.yml)  
[![LineageOS Leaks Tracker](https://github.com/programminghoch10/tracker-collection/actions/workflows/lineageos-leaks.yml/badge.svg)](https://github.com/programminghoch10/tracker-collection/actions/workflows/lineageos-leaks.yml)  
[![GitHub Releases Tracker](https://github.com/programminghoch10/tracker-collection/actions/workflows/github-releases.yml/badge.svg)](https://github.com/programminghoch10/tracker-collection/actions/workflows/github-releases.yml)  
[![Magisk Modules Tracker](https://github.com/programminghoch10/tracker-collection/actions/workflows/magisk-modules.yml/badge.svg)](https://github.com/programminghoch10/tracker-collection/actions/workflows/magisk-modules.yml)  

## Rules & Guidelines

All trackers run on GitHub Actions on a schedule.

This is a kinda niche UseCase of GitHub Actions.  
Though as far as me and my friend interpreted the 
[GitHub Actions Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features#actions)
about anything is allowed 
as long as it's not illegal 
or imposing an artificially high workload 
onto their servers.  
_(Please correct me if I'm wrong @GitHub)_

Therefore all trackers are optimized 
primarily for low workload 
and secondarily for short execution times.  
This is why the use of `sleep` is preferred, 
as during sleeping 
literally no workload lies upon 
the hosting action runner.

The trackers are also scheduled for sane times, 
mostly once a day, 
except for real time update trackers.

Trackers connecting to other servers for acquiring data 
must also adhere to their timeouts 
_(or if not specified at least use sane intervals)_
to not annoy the other servers.

[![ShellCheck](https://github.com/programminghoch10/tracker-collection/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/programminghoch10/tracker-collection/actions/workflows/shellcheck.yml)  

All trackers must be written purely in BASH
with the least amount of additional software
as possible.  
This also ensures that the least amount 
of time/work of the runner 
is spent on preparing the environment 
for the actual tracker run.

Tracker data has to be saved on a unique branch per tracker, 
preferably named 
`trackdata-`_&lt;`folder`&gt;_.  
Touching the `main` branch is forbidden.
