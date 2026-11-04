# Model check, 2026-11-04 05:35 UTC

36 forecast runs stored (2026-10-23T20:00Z to 2026-11-04T05:00Z).
Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.
"Light wrong" = how often wind and gusts alone would have given a different rowing light than measured.
Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.

## All points, day 1

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 8530 | 1.4 | +0.0 | 2.6 | 1.1 | 26 % |
| best_match | 8530 | 1.5 | +0.2 | 2.6 | 1.3 | 26 % |
| **icon_d2** (app today) | 8530 | 1.5 | +0.2 | 2.6 | 1.3 | 26 % |
| ecmwf_aifs025_single | 8530 | 1.5 | +0.3 | – | 1.1 | – |
| knmi_harmonie_arome_europe | 8530 | 1.6 | +0.5 | 2.6 | 1.2 | 26 % |
| ecmwf_ifs025 | 8530 | 1.6 | +0.7 | 2.6 | 1.2 | 31 % |
| dmi_harmonie_arome_europe | 8530 | 1.7 | +0.7 | 2.9 | 1.2 | 30 % |
| meteoswiss_icon_ch2 | 8530 | 1.7 | +0.8 | 2.8 | 1.4 | 29 % |
| meteoswiss_icon_ch1 | 8520 | 1.9 | +1.0 | 2.9 | 1.5 | 30 % |
| geosphere_arome_austria | 8530 | 1.9 | +0.8 | 2.7 | 1.7 | 26 % |

## All points, day 2

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 7390 | 1.0 | -0.2 | 2.0 | 1.1 | 17 % |
| best_match | 7390 | 1.1 | -0.0 | 2.1 | 1.3 | 19 % |
| **icon_d2** (app today) | 7100 | 1.1 | -0.0 | 2.1 | 1.3 | 19 % |
| ecmwf_aifs025_single | 7390 | 1.1 | +0.3 | – | 1.2 | – |
| meteoswiss_icon_ch2 | 7390 | 1.2 | +0.4 | 2.1 | 1.4 | 19 % |
| ecmwf_ifs025 | 7390 | 1.2 | +0.4 | 2.0 | 1.2 | 23 % |
| knmi_harmonie_arome_europe | 7390 | 1.2 | +0.2 | 2.0 | 1.4 | 18 % |
| dmi_harmonie_arome_europe | 7390 | 1.3 | +0.3 | 2.2 | 1.4 | 20 % |
| geosphere_arome_austria | 7390 | 1.3 | +0.3 | 2.0 | 2.0 | 15 % |
| meteoswiss_icon_ch1 | 2070 | 1.5 | +0.8 | 2.2 | 1.5 | 24 % |

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
| icon_eu | 6530 | 2700 | 1.20 | 1.00 | 21 % | 17 % |
| best_match | 6530 | 2700 | 1.28 | 1.08 | 22 % | 18 % |
| icon_d2 | 6530 | 2700 | 1.28 | 1.08 | 22 % | 18 % |
| ecmwf_aifs025_single | 6530 | 2700 | 1.30 | 1.08 | – | – |
| ecmwf_ifs025 | 6530 | 2700 | 1.40 | 1.16 | 24 % | 19 % |
| knmi_harmonie_arome_europe | 6530 | 2700 | 1.41 | 1.18 | 21 % | 15 % |
| meteoswiss_icon_ch2 | 6530 | 2700 | 1.46 | 1.16 | 24 % | 19 % |
| dmi_harmonie_arome_europe | 6530 | 2700 | 1.46 | 1.21 | 24 % | 18 % |
| meteoswiss_icon_ch1 | 6520 | 2690 | 1.63 | 1.34 | 25 % | 20 % |
| geosphere_arome_austria | 6530 | 2700 | 1.64 | 1.29 | 20 % | 15 % |

Same order of the models with one run a day: **no** (twice: icon_eu, best_match, icon_d2; once: icon_eu, best_match, icon_d2).

## icon_d2 vs best_match

128 forecast hours differ by more than wind 2.0 m/s, gusts 3.0 m/s or air 2.0 °C.

| Point | Hours |
| --- | --- |
| starnberger-see-south | 47 |
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
| icon_eu | 853 | 1.2 | +0.6 | 2.3 | 0.9 | 29 % |
| best_match | 853 | 1.2 | +0.6 | 1.7 | 1.0 | 18 % |
| **icon_d2** (app today) | 853 | 1.2 | +0.6 | 1.7 | 1.0 | 18 % |
| knmi_harmonie_arome_europe | 853 | 1.4 | +0.7 | 2.3 | 0.9 | 24 % |
| meteoswiss_icon_ch2 | 853 | 1.4 | +1.1 | 1.9 | 1.0 | 19 % |
| ecmwf_aifs025_single | 853 | 1.4 | +1.1 | – | 1.0 | – |
| meteoswiss_icon_ch1 | 852 | 1.5 | +1.1 | 2.4 | 1.1 | 24 % |
| dmi_harmonie_arome_europe | 853 | 1.5 | +1.0 | 2.2 | 1.0 | 24 % |
| geosphere_arome_austria | 853 | 1.6 | +1.1 | 2.3 | 1.4 | 19 % |
| ecmwf_ifs025 | 853 | 1.6 | +1.3 | 2.6 | 1.0 | 32 % |

### Tutzinger RV launch point

Stations: wind: Wielenbach (Demollstr.) (8.9 km), gust: Wielenbach (Demollstr.) (8.9 km), temp: Attenkam (6.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 853 | 0.9 | +0.3 | 1.5 | 1.0 | 17 % |
| **icon_d2** (app today) | 853 | 0.9 | +0.3 | 1.5 | 1.0 | 17 % |
| icon_eu | 853 | 1.0 | +0.6 | 1.9 | 1.0 | 25 % |
| geosphere_arome_austria | 853 | 1.1 | +0.5 | 2.1 | 1.4 | 22 % |
| knmi_harmonie_arome_europe | 853 | 1.1 | +0.2 | 1.7 | 1.0 | 19 % |
| dmi_harmonie_arome_europe | 853 | 1.3 | +0.7 | 2.4 | 0.9 | 24 % |
| meteoswiss_icon_ch2 | 853 | 1.4 | +1.2 | 1.9 | 1.5 | 20 % |
| ecmwf_aifs025_single | 853 | 1.4 | +1.1 | – | 1.0 | – |
| ecmwf_ifs025 | 853 | 1.6 | +1.3 | 2.6 | 1.0 | 32 % |
| meteoswiss_icon_ch1 | 852 | 1.6 | +1.5 | 2.3 | 1.3 | 28 % |

### Starnberger See, centre

Stations: wind: Wielenbach (Demollstr.) (11.4 km), gust: Wielenbach (Demollstr.) (11.4 km), temp: Attenkam (5.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| **icon_d2** (app today) | 853 | 1.2 | +0.8 | 1.8 | 1.0 | 18 % |
| best_match | 853 | 1.2 | +0.9 | 1.8 | 1.0 | 18 % |
| icon_eu | 853 | 1.2 | +0.9 | 1.5 | 1.1 | 19 % |
| ecmwf_aifs025_single | 853 | 1.4 | +1.1 | – | 1.0 | – |
| ecmwf_ifs025 | 853 | 1.6 | +1.3 | 2.6 | 1.0 | 32 % |
| knmi_harmonie_arome_europe | 853 | 1.6 | +1.3 | 2.6 | 1.0 | 25 % |
| meteoswiss_icon_ch2 | 853 | 1.6 | +1.5 | 2.6 | 1.3 | 26 % |
| dmi_harmonie_arome_europe | 853 | 1.9 | +1.6 | 3.1 | 1.1 | 31 % |
| geosphere_arome_austria | 853 | 2.0 | +1.9 | 2.2 | 1.5 | 22 % |
| meteoswiss_icon_ch1 | 852 | 2.6 | +2.6 | 2.3 | 1.9 | 26 % |

### Starnberger See, south near Seeshaupt

Stations: wind: Wielenbach (Demollstr.) (13.6 km), gust: Wielenbach (Demollstr.) (13.6 km), temp: Attenkam (5.6 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 853 | 0.9 | -0.1 | 1.6 | 1.0 | 20 % |
| best_match | 853 | 0.9 | -0.0 | 1.5 | 1.1 | 18 % |
| **icon_d2** (app today) | 853 | 0.9 | -0.0 | 1.5 | 1.1 | 18 % |
| meteoswiss_icon_ch1 | 852 | 1.1 | +0.6 | 1.7 | 1.2 | 20 % |
| knmi_harmonie_arome_europe | 853 | 1.2 | +0.1 | 1.8 | 1.0 | 18 % |
| dmi_harmonie_arome_europe | 853 | 1.2 | +0.4 | 2.0 | 1.0 | 20 % |
| ecmwf_aifs025_single | 853 | 1.2 | -0.0 | – | 0.9 | – |
| ecmwf_ifs025 | 853 | 1.2 | +0.5 | 2.1 | 1.1 | 28 % |
| geosphere_arome_austria | 853 | 1.5 | +1.1 | 1.8 | 1.6 | 19 % |
| meteoswiss_icon_ch2 | 853 | 1.6 | +1.4 | 2.2 | 1.7 | 24 % |

### Ammersee, centre

Stations: wind: Wielenbach (Demollstr.) (13.3 km), gust: Wielenbach (Demollstr.) (13.3 km), temp: Wielenbach (Demollstr.) (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 853 | 1.5 | +1.1 | 2.2 | 1.4 | 24 % |
| best_match | 853 | 1.6 | +1.2 | 2.0 | 1.5 | 21 % |
| **icon_d2** (app today) | 853 | 1.6 | +1.2 | 2.0 | 1.5 | 21 % |
| meteoswiss_icon_ch2 | 853 | 1.6 | +1.3 | 2.5 | 1.3 | 25 % |
| ecmwf_aifs025_single | 853 | 1.7 | +1.4 | – | 1.4 | – |
| dmi_harmonie_arome_europe | 853 | 1.8 | +1.3 | 3.8 | 1.6 | 36 % |
| ecmwf_ifs025 | 853 | 2.0 | +1.8 | 3.2 | 1.3 | 38 % |
| knmi_harmonie_arome_europe | 853 | 2.1 | +1.8 | 3.2 | 1.6 | 30 % |
| meteoswiss_icon_ch1 | 852 | 2.4 | +2.2 | 2.4 | 2.9 | 26 % |
| geosphere_arome_austria | 853 | 2.8 | +2.5 | 3.1 | 1.8 | 28 % |

### Wörthsee, centre

Stations: wind: Wielenbach (Demollstr.) (20.6 km), gust: Wielenbach (Demollstr.) (20.6 km), temp: Maisach-Galgen (15.7 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 853 | 1.4 | +1.0 | 1.9 | 1.1 | 21 % |
| **icon_d2** (app today) | 853 | 1.4 | +1.0 | 1.9 | 1.1 | 21 % |
| ecmwf_aifs025_single | 853 | 1.4 | +1.1 | – | 0.9 | – |
| icon_eu | 853 | 1.5 | +1.2 | 2.5 | 0.9 | 29 % |
| ecmwf_ifs025 | 853 | 1.6 | +1.3 | 2.6 | 1.0 | 32 % |
| knmi_harmonie_arome_europe | 853 | 1.6 | +1.3 | 2.5 | 0.8 | 24 % |
| meteoswiss_icon_ch2 | 853 | 1.8 | +1.6 | 2.5 | 0.8 | 26 % |
| geosphere_arome_austria | 853 | 1.9 | +1.5 | 3.0 | 1.2 | 26 % |
| dmi_harmonie_arome_europe | 853 | 2.0 | +1.8 | 2.7 | 0.8 | 27 % |
| meteoswiss_icon_ch1 | 852 | 2.0 | +1.9 | 2.8 | 0.9 | 26 % |

### Tegernsee, centre

Stations: wind: Kreuth (9.0 km), gust: Bichl (25.7 km), temp: Kreuth (9.0 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 853 | 1.0 | +0.8 | 4.4 | 1.3 | 34 % |
| ecmwf_aifs025_single | 853 | 1.1 | +1.0 | – | 1.6 | – |
| knmi_harmonie_arome_europe | 853 | 2.1 | +2.0 | 4.0 | 1.6 | 36 % |
| ecmwf_ifs025 | 853 | 2.1 | +2.0 | 3.0 | 2.1 | 31 % |
| dmi_harmonie_arome_europe | 853 | 2.2 | +2.1 | 4.3 | 1.8 | 45 % |
| **icon_d2** (app today) | 853 | 2.2 | +2.1 | 6.6 | 1.6 | 67 % |
| best_match | 853 | 2.2 | +2.1 | 6.6 | 1.6 | 67 % |
| geosphere_arome_austria | 853 | 2.3 | +2.0 | 3.5 | 2.5 | 31 % |
| meteoswiss_icon_ch2 | 853 | 2.5 | +2.4 | 6.6 | 1.6 | 66 % |
| meteoswiss_icon_ch1 | 852 | 2.8 | +2.7 | 7.0 | 1.6 | 68 % |

### Kochelsee, centre

Stations: wind: Bichl (8.9 km), gust: Bichl (8.9 km), temp: Bichl (8.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 853 | 0.9 | -0.2 | – | 1.1 | – |
| meteoswiss_icon_ch2 | 853 | 1.0 | -0.3 | 2.0 | 1.7 | 16 % |
| ecmwf_ifs025 | 853 | 1.0 | +0.3 | 1.8 | 1.2 | 20 % |
| best_match | 853 | 1.1 | -0.6 | 2.0 | 1.3 | 15 % |
| **icon_d2** (app today) | 853 | 1.1 | -0.6 | 2.0 | 1.3 | 15 % |
| knmi_harmonie_arome_europe | 853 | 1.1 | +0.2 | 1.8 | 1.4 | 20 % |
| icon_eu | 853 | 1.2 | -0.9 | 1.8 | 0.9 | 16 % |
| meteoswiss_icon_ch1 | 852 | 1.2 | -0.4 | 2.0 | 1.2 | 21 % |
| geosphere_arome_austria | 853 | 1.2 | -0.4 | 2.4 | 1.9 | 22 % |
| dmi_harmonie_arome_europe | 853 | 1.2 | +0.1 | 2.1 | 1.3 | 24 % |

### Staffelsee, centre

Stations: wind: Hohenpeißenberg (16.9 km), gust: Hohenpeißenberg (16.9 km), temp: Kohlgrub, Bad (Rosshof) (7.4 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| meteoswiss_icon_ch1 | 852 | 2.6 | -2.4 | 4.1 | 2.1 | 38 % |
| dmi_harmonie_arome_europe | 853 | 2.9 | -2.8 | 5.0 | 1.4 | 49 % |
| ecmwf_ifs025 | 853 | 2.9 | -2.9 | 4.4 | 1.1 | 47 % |
| meteoswiss_icon_ch2 | 853 | 3.0 | -3.0 | 5.0 | 2.2 | 45 % |
| knmi_harmonie_arome_europe | 853 | 3.1 | -3.0 | 5.0 | 1.3 | 47 % |
| geosphere_arome_austria | 853 | 3.2 | -3.1 | 5.2 | 1.8 | 49 % |
| ecmwf_aifs025_single | 853 | 3.4 | -3.4 | – | 0.9 | – |
| best_match | 853 | 3.5 | -3.5 | 5.9 | 2.2 | 51 % |
| **icon_d2** (app today) | 853 | 3.5 | -3.5 | 5.9 | 2.2 | 51 % |
| icon_eu | 853 | 3.5 | -3.5 | 6.4 | 1.3 | 53 % |

### Olympic regatta course Oberschleißheim

Stations: wind: München-Stadt (9.2 km), gust: München-Stadt (9.2 km), temp: München-Stadt (9.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 853 | 0.7 | -0.2 | 1.2 | 1.0 | 17 % |
| **icon_d2** (app today) | 853 | 0.7 | -0.2 | 1.2 | 1.0 | 17 % |
| icon_eu | 853 | 0.7 | -0.2 | 1.3 | 0.9 | 15 % |
| ecmwf_aifs025_single | 853 | 0.7 | +0.4 | – | 1.0 | – |
| meteoswiss_icon_ch2 | 853 | 0.8 | +0.3 | 1.3 | 1.1 | 20 % |
| knmi_harmonie_arome_europe | 853 | 0.8 | +0.2 | 1.5 | 1.2 | 20 % |
| ecmwf_ifs025 | 853 | 0.8 | +0.4 | 1.3 | 1.3 | 23 % |
| meteoswiss_icon_ch1 | 852 | 0.8 | +0.4 | 1.5 | 1.1 | 23 % |
| dmi_harmonie_arome_europe | 853 | 0.8 | +0.3 | 1.5 | 1.2 | 23 % |
| geosphere_arome_austria | 853 | 1.2 | +0.7 | 1.7 | 1.9 | 21 % |

Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0).
