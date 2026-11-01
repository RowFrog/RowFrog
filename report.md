# Model check, 2026-11-01 17:11 UTC

31 forecast runs stored (2026-10-23T20:00Z to 2026-11-01T17:00Z).
Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.
"Light wrong" = how often wind and gusts alone would have given a different rowing light than measured.
Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.

## All points, day 1

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 7030 | 1.5 | +0.1 | 2.8 | 1.1 | 27 % |
| best_match | 7030 | 1.6 | +0.2 | 2.7 | 1.3 | 26 % |
| **icon_d2** (app today) | 7030 | 1.6 | +0.2 | 2.8 | 1.3 | 26 % |
| ecmwf_aifs025_single | 7030 | 1.6 | +0.4 | – | 1.1 | – |
| knmi_harmonie_arome_europe | 7030 | 1.7 | +0.6 | 2.8 | 1.2 | 27 % |
| dmi_harmonie_arome_europe | 7030 | 1.8 | +0.8 | 3.1 | 1.2 | 32 % |
| ecmwf_ifs025 | 7030 | 1.8 | +0.8 | 2.9 | 1.2 | 34 % |
| meteoswiss_icon_ch2 | 7030 | 1.8 | +0.8 | 3.0 | 1.4 | 29 % |
| meteoswiss_icon_ch1 | 7020 | 2.0 | +1.0 | 3.0 | 1.5 | 30 % |
| geosphere_arome_austria | 7030 | 2.0 | +0.9 | 2.9 | 1.7 | 27 % |

## All points, day 2

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 6010 | 1.1 | -0.1 | 2.1 | 1.1 | 16 % |
| best_match | 6010 | 1.2 | -0.1 | 2.1 | 1.3 | 17 % |
| **icon_d2** (app today) | 5780 | 1.2 | -0.0 | 2.1 | 1.3 | 16 % |
| ecmwf_aifs025_single | 6010 | 1.2 | +0.3 | – | 1.2 | – |
| knmi_harmonie_arome_europe | 6010 | 1.2 | +0.3 | 2.1 | 1.5 | 17 % |
| meteoswiss_icon_ch2 | 6010 | 1.3 | +0.4 | 2.1 | 1.4 | 17 % |
| ecmwf_ifs025 | 6010 | 1.3 | +0.5 | 2.1 | 1.3 | 24 % |
| dmi_harmonie_arome_europe | 6010 | 1.3 | +0.4 | 2.2 | 1.4 | 20 % |
| geosphere_arome_austria | 6010 | 1.3 | +0.4 | 2.0 | 2.1 | 14 % |
| meteoswiss_icon_ch1 | 1650 | 1.5 | +0.8 | 2.2 | 1.5 | 22 % |

## All points, archive

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 14385 | 0.8 | -0.0 | 1.7 | 1.2 | 10 % |
| **icon_d2** (app today) | 14385 | 0.9 | +0.2 | 1.6 | 1.4 | 9 % |
| best_match | 14385 | 0.9 | +0.2 | 1.6 | 1.4 | 9 % |
| ecmwf_aifs025_single | 14385 | 0.9 | +0.1 | – | 1.4 | – |
| knmi_harmonie_arome_europe | 14385 | 1.0 | +0.2 | 1.6 | 1.3 | 8 % |
| ecmwf_ifs025 | 14385 | 1.0 | +0.3 | 1.8 | 1.2 | 11 % |
| meteoswiss_icon_ch2 | 14385 | 1.0 | +0.4 | 2.0 | 1.5 | 12 % |
| dmi_harmonie_arome_europe | 14385 | 1.1 | +0.3 | 1.8 | 1.3 | 10 % |
| geosphere_arome_austria | 14385 | 1.1 | +0.4 | 1.6 | 1.7 | 10 % |
| meteoswiss_icon_ch1 | 14385 | 1.1 | +0.5 | 1.9 | 1.6 | 11 % |

## Once a day instead of twice?

Day 1 over all points, from the two scheduled runs (04:40 and 16:40 UTC) and from the 04:40 run alone.

| Model | Hours, twice | Hours, once | Wind error, twice | Wind error, once | Light wrong, twice | Light wrong, once |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 5030 | 1950 | 1.29 | 1.03 | 20 % | 15 % |
| best_match | 5030 | 1950 | 1.35 | 1.07 | 20 % | 14 % |
| icon_d2 | 5030 | 1950 | 1.35 | 1.07 | 20 % | 14 % |
| ecmwf_aifs025_single | 5030 | 1950 | 1.40 | 1.12 | – | – |
| knmi_harmonie_arome_europe | 5030 | 1950 | 1.50 | 1.19 | 21 % | 13 % |
| ecmwf_ifs025 | 5030 | 1950 | 1.54 | 1.24 | 25 % | 18 % |
| dmi_harmonie_arome_europe | 5030 | 1950 | 1.54 | 1.23 | 24 % | 15 % |
| meteoswiss_icon_ch2 | 5030 | 1950 | 1.57 | 1.20 | 22 % | 15 % |
| meteoswiss_icon_ch1 | 5020 | 1940 | 1.71 | 1.32 | 24 % | 17 % |
| geosphere_arome_austria | 5030 | 1950 | 1.74 | 1.31 | 20 % | 13 % |

Same order of the models with one run a day: **no** (twice: icon_eu, best_match, icon_d2; once: icon_eu, best_match, icon_d2).

## icon_d2 vs best_match

127 forecast hours differ by more than wind 2.0 m/s, gusts 3.0 m/s or air 2.0 °C.

| Point | Hours |
| --- | --- |
| starnberger-see-south | 46 |
| staffelsee | 34 |
| starnberger-see-centre | 18 |
| tegernsee | 15 |
| kochelsee | 10 |
| tutzinger-rv | 3 |
| ammersee | 1 |

Latest:

| Run | Point | Hour | Differences |
| --- | --- | --- | --- |
| archive | staffelsee | 2026-10-03T00:00Z | temp +2.3 |
| archive | staffelsee | 2026-10-03T01:00Z | temp +2.2 |
| archive | staffelsee | 2026-10-04T00:00Z | temp -2.3 |
| archive | staffelsee | 2026-10-05T18:00Z | temp -2.1 |
| archive | staffelsee | 2026-10-07T00:00Z | temp -2.2 |
| archive | staffelsee | 2026-10-07T18:00Z | temp -2.4 |
| archive | staffelsee | 2026-10-12T18:00Z | temp -2.2 |
| archive | staffelsee | 2026-10-12T22:00Z | temp -2.2 |
| archive | staffelsee | 2026-10-13T04:00Z | temp -2.1 |
| archive | staffelsee | 2026-10-13T19:00Z | temp -2.1 |

## Per point (day 1)

### MRC 1880 launch point, Starnberg

Stations: wind: Wielenbach (Demollstr.) (19.0 km), gust: Wielenbach (Demollstr.) (19.0 km), temp: Attenkam (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 703 | 1.3 | +0.8 | 2.5 | 0.9 | 29 % |
| best_match | 703 | 1.3 | +0.8 | 1.8 | 1.0 | 17 % |
| **icon_d2** (app today) | 703 | 1.3 | +0.8 | 1.8 | 1.0 | 17 % |
| knmi_harmonie_arome_europe | 703 | 1.4 | +1.0 | 2.5 | 0.9 | 25 % |
| ecmwf_aifs025_single | 703 | 1.6 | +1.3 | – | 1.0 | – |
| meteoswiss_icon_ch2 | 703 | 1.6 | +1.4 | 2.1 | 1.1 | 19 % |
| dmi_harmonie_arome_europe | 703 | 1.6 | +1.3 | 2.4 | 1.0 | 25 % |
| meteoswiss_icon_ch1 | 702 | 1.7 | +1.4 | 2.6 | 1.1 | 25 % |
| geosphere_arome_austria | 703 | 1.7 | +1.4 | 2.4 | 1.4 | 20 % |
| ecmwf_ifs025 | 703 | 1.7 | +1.5 | 2.9 | 0.9 | 34 % |

### Tutzinger RV launch point

Stations: wind: Wielenbach (Demollstr.) (8.9 km), gust: Wielenbach (Demollstr.) (8.9 km), temp: Attenkam (6.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| **icon_d2** (app today) | 703 | 0.9 | +0.3 | 1.5 | 1.0 | 16 % |
| best_match | 703 | 0.9 | +0.3 | 1.5 | 1.0 | 16 % |
| icon_eu | 703 | 1.0 | +0.6 | 1.9 | 1.0 | 23 % |
| knmi_harmonie_arome_europe | 703 | 1.1 | +0.4 | 1.8 | 1.1 | 18 % |
| geosphere_arome_austria | 703 | 1.1 | +0.6 | 2.2 | 1.6 | 22 % |
| dmi_harmonie_arome_europe | 703 | 1.3 | +0.8 | 2.5 | 0.9 | 25 % |
| meteoswiss_icon_ch2 | 703 | 1.4 | +1.2 | 1.9 | 1.4 | 18 % |
| meteoswiss_icon_ch1 | 702 | 1.5 | +1.3 | 2.1 | 1.2 | 24 % |
| ecmwf_aifs025_single | 703 | 1.6 | +1.3 | – | 1.0 | – |
| ecmwf_ifs025 | 703 | 1.7 | +1.5 | 2.9 | 0.9 | 34 % |

### Starnberger See, centre

Stations: wind: Wielenbach (Demollstr.) (11.4 km), gust: Wielenbach (Demollstr.) (11.4 km), temp: Attenkam (5.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 703 | 1.3 | +0.9 | 1.6 | 1.1 | 19 % |
| best_match | 703 | 1.3 | +1.0 | 1.9 | 1.0 | 18 % |
| **icon_d2** (app today) | 703 | 1.3 | +1.0 | 1.9 | 1.0 | 18 % |
| ecmwf_aifs025_single | 703 | 1.6 | +1.3 | – | 1.0 | – |
| ecmwf_ifs025 | 703 | 1.7 | +1.5 | 2.9 | 0.9 | 34 % |
| knmi_harmonie_arome_europe | 703 | 1.8 | +1.5 | 2.8 | 1.0 | 26 % |
| meteoswiss_icon_ch2 | 703 | 1.8 | +1.7 | 2.7 | 1.4 | 26 % |
| dmi_harmonie_arome_europe | 703 | 2.0 | +1.9 | 3.4 | 1.1 | 34 % |
| geosphere_arome_austria | 703 | 2.1 | +2.0 | 2.3 | 1.6 | 22 % |
| meteoswiss_icon_ch1 | 702 | 2.8 | +2.7 | 2.5 | 1.9 | 26 % |

### Starnberger See, south near Seeshaupt

Stations: wind: Wielenbach (Demollstr.) (13.6 km), gust: Wielenbach (Demollstr.) (13.6 km), temp: Attenkam (5.6 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 703 | 0.9 | +0.0 | 1.5 | 1.1 | 18 % |
| **icon_d2** (app today) | 703 | 0.9 | +0.0 | 1.5 | 1.1 | 18 % |
| icon_eu | 703 | 0.9 | -0.1 | 1.7 | 1.1 | 20 % |
| knmi_harmonie_arome_europe | 703 | 1.1 | +0.2 | 1.9 | 1.0 | 18 % |
| meteoswiss_icon_ch1 | 702 | 1.1 | +0.6 | 1.8 | 1.2 | 19 % |
| dmi_harmonie_arome_europe | 703 | 1.2 | +0.6 | 2.1 | 1.0 | 21 % |
| ecmwf_aifs025_single | 703 | 1.2 | +0.2 | – | 1.0 | – |
| ecmwf_ifs025 | 703 | 1.3 | +0.6 | 2.3 | 1.2 | 29 % |
| geosphere_arome_austria | 703 | 1.6 | +1.4 | 1.8 | 1.8 | 18 % |
| meteoswiss_icon_ch2 | 703 | 1.7 | +1.5 | 2.3 | 1.7 | 25 % |

### Ammersee, centre

Stations: wind: Wielenbach (Demollstr.) (13.3 km), gust: Wielenbach (Demollstr.) (13.3 km), temp: Wielenbach (Demollstr.) (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 703 | 1.7 | +1.3 | 2.4 | 1.5 | 25 % |
| best_match | 703 | 1.7 | +1.4 | 2.1 | 1.5 | 21 % |
| **icon_d2** (app today) | 703 | 1.7 | +1.4 | 2.1 | 1.5 | 21 % |
| meteoswiss_icon_ch2 | 703 | 1.8 | +1.5 | 2.8 | 1.4 | 26 % |
| ecmwf_aifs025_single | 703 | 1.9 | +1.6 | – | 1.5 | – |
| dmi_harmonie_arome_europe | 703 | 1.9 | +1.6 | 4.2 | 1.7 | 39 % |
| ecmwf_ifs025 | 703 | 2.2 | +2.1 | 3.5 | 1.4 | 41 % |
| knmi_harmonie_arome_europe | 703 | 2.3 | +2.2 | 3.5 | 1.7 | 32 % |
| meteoswiss_icon_ch1 | 702 | 2.6 | +2.4 | 2.6 | 2.9 | 27 % |
| geosphere_arome_austria | 703 | 3.2 | +3.0 | 3.3 | 1.8 | 29 % |

### Wörthsee, centre

Stations: wind: Wielenbach (Demollstr.) (20.6 km), gust: Wielenbach (Demollstr.) (20.6 km), temp: Maisach-Galgen (15.7 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| **icon_d2** (app today) | 703 | 1.6 | +1.2 | 2.0 | 1.2 | 21 % |
| best_match | 703 | 1.6 | +1.2 | 2.0 | 1.2 | 21 % |
| ecmwf_aifs025_single | 703 | 1.6 | +1.3 | – | 0.9 | – |
| icon_eu | 703 | 1.7 | +1.4 | 2.7 | 0.9 | 29 % |
| ecmwf_ifs025 | 703 | 1.7 | +1.5 | 2.9 | 1.0 | 34 % |
| knmi_harmonie_arome_europe | 703 | 1.8 | +1.5 | 2.7 | 0.8 | 25 % |
| meteoswiss_icon_ch2 | 703 | 1.9 | +1.8 | 2.8 | 0.8 | 27 % |
| geosphere_arome_austria | 703 | 2.1 | +1.8 | 3.2 | 1.1 | 27 % |
| meteoswiss_icon_ch1 | 702 | 2.2 | +2.0 | 3.0 | 0.9 | 26 % |
| dmi_harmonie_arome_europe | 703 | 2.2 | +2.1 | 2.9 | 0.9 | 29 % |

### Tegernsee, centre

Stations: wind: Kreuth (9.0 km), gust: Bichl (25.7 km), temp: Kreuth (9.0 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 703 | 1.1 | +0.8 | 4.8 | 1.2 | 40 % |
| ecmwf_aifs025_single | 703 | 1.1 | +0.9 | – | 1.6 | – |
| dmi_harmonie_arome_europe | 703 | 2.1 | +2.1 | 4.4 | 1.6 | 44 % |
| knmi_harmonie_arome_europe | 703 | 2.1 | +2.1 | 4.2 | 1.4 | 40 % |
| **icon_d2** (app today) | 703 | 2.1 | +2.0 | 6.8 | 1.4 | 62 % |
| best_match | 703 | 2.1 | +2.0 | 6.8 | 1.4 | 62 % |
| ecmwf_ifs025 | 703 | 2.2 | +2.0 | 3.2 | 1.9 | 36 % |
| geosphere_arome_austria | 703 | 2.3 | +1.9 | 3.7 | 2.2 | 35 % |
| meteoswiss_icon_ch2 | 703 | 2.5 | +2.4 | 6.7 | 1.4 | 61 % |
| meteoswiss_icon_ch1 | 702 | 2.8 | +2.6 | 7.1 | 1.5 | 63 % |

### Kochelsee, centre

Stations: wind: Bichl (8.9 km), gust: Bichl (8.9 km), temp: Bichl (8.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 703 | 0.9 | -0.2 | – | 1.1 | – |
| ecmwf_ifs025 | 703 | 1.0 | +0.2 | 1.8 | 1.3 | 19 % |
| meteoswiss_icon_ch2 | 703 | 1.1 | -0.3 | 2.0 | 1.8 | 18 % |
| knmi_harmonie_arome_europe | 703 | 1.2 | +0.0 | 1.9 | 1.4 | 21 % |
| best_match | 703 | 1.2 | -0.7 | 2.0 | 1.3 | 17 % |
| **icon_d2** (app today) | 703 | 1.2 | -0.7 | 2.0 | 1.3 | 17 % |
| geosphere_arome_austria | 703 | 1.2 | -0.3 | 2.3 | 2.0 | 25 % |
| dmi_harmonie_arome_europe | 703 | 1.2 | +0.2 | 2.1 | 1.3 | 27 % |
| meteoswiss_icon_ch1 | 702 | 1.2 | -0.4 | 2.1 | 1.2 | 25 % |
| icon_eu | 703 | 1.2 | -0.9 | 1.9 | 0.9 | 18 % |

### Staffelsee, centre

Stations: wind: Hohenpeißenberg (16.9 km), gust: Hohenpeißenberg (16.9 km), temp: Kohlgrub, Bad (Rosshof) (7.4 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| meteoswiss_icon_ch1 | 702 | 2.9 | -2.8 | 4.6 | 2.2 | 41 % |
| dmi_harmonie_arome_europe | 703 | 3.2 | -3.1 | 5.5 | 1.4 | 50 % |
| ecmwf_ifs025 | 703 | 3.3 | -3.3 | 5.0 | 1.1 | 50 % |
| geosphere_arome_austria | 703 | 3.4 | -3.3 | 5.5 | 1.9 | 50 % |
| meteoswiss_icon_ch2 | 703 | 3.4 | -3.4 | 5.6 | 2.3 | 49 % |
| knmi_harmonie_arome_europe | 703 | 3.4 | -3.3 | 5.5 | 1.4 | 48 % |
| ecmwf_aifs025_single | 703 | 3.7 | -3.7 | – | 1.0 | – |
| icon_eu | 703 | 3.8 | -3.8 | 6.9 | 1.4 | 54 % |
| **icon_d2** (app today) | 703 | 3.9 | -3.9 | 6.7 | 2.3 | 52 % |
| best_match | 703 | 3.9 | -3.9 | 6.7 | 2.3 | 52 % |

### Olympic regatta course Oberschleißheim

Stations: wind: München-Stadt (9.2 km), gust: München-Stadt (9.2 km), temp: München-Stadt (9.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 703 | 0.7 | -0.1 | 1.2 | 1.0 | 15 % |
| best_match | 703 | 0.7 | -0.1 | 1.2 | 1.0 | 17 % |
| **icon_d2** (app today) | 703 | 0.7 | -0.1 | 1.2 | 1.0 | 17 % |
| meteoswiss_icon_ch2 | 703 | 0.8 | +0.3 | 1.3 | 1.1 | 20 % |
| ecmwf_aifs025_single | 703 | 0.8 | +0.4 | – | 1.1 | – |
| knmi_harmonie_arome_europe | 703 | 0.8 | +0.3 | 1.5 | 1.3 | 22 % |
| ecmwf_ifs025 | 703 | 0.8 | +0.4 | 1.4 | 1.3 | 24 % |
| meteoswiss_icon_ch1 | 702 | 0.9 | +0.5 | 1.5 | 1.1 | 24 % |
| dmi_harmonie_arome_europe | 703 | 0.9 | +0.3 | 1.6 | 1.3 | 25 % |
| geosphere_arome_austria | 703 | 1.3 | +0.9 | 1.8 | 1.9 | 23 % |

Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0).
