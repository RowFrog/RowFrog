# Model check, 2026-10-31 05:18 UTC

28 forecast runs stored (2026-10-23T20:00Z to 2026-10-31T05:00Z).
Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.
"Light wrong" = how often wind and gusts alone would have given a different rowing light than measured.
Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.

## All points, day 1

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 6530 | 1.5 | +0.1 | 2.8 | 1.1 | 29 % |
| best_match | 6530 | 1.6 | +0.2 | 2.8 | 1.3 | 27 % |
| **icon_d2** (app today) | 6530 | 1.6 | +0.2 | 2.8 | 1.3 | 27 % |
| ecmwf_aifs025_single | 6530 | 1.6 | +0.5 | – | 1.1 | – |
| knmi_harmonie_arome_europe | 6530 | 1.8 | +0.6 | 2.9 | 1.2 | 29 % |
| dmi_harmonie_arome_europe | 6530 | 1.8 | +0.8 | 3.2 | 1.2 | 34 % |
| ecmwf_ifs025 | 6530 | 1.8 | +0.8 | 2.9 | 1.2 | 36 % |
| meteoswiss_icon_ch2 | 6530 | 1.8 | +0.8 | 3.1 | 1.4 | 31 % |
| meteoswiss_icon_ch1 | 6520 | 2.0 | +1.1 | 3.1 | 1.5 | 32 % |
| geosphere_arome_austria | 6530 | 2.1 | +1.0 | 3.0 | 1.8 | 29 % |

## All points, day 2

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 5550 | 1.1 | -0.1 | 2.1 | 1.1 | 16 % |
| best_match | 5550 | 1.2 | -0.1 | 2.2 | 1.3 | 17 % |
| **icon_d2** (app today) | 5340 | 1.2 | -0.0 | 2.2 | 1.3 | 17 % |
| ecmwf_aifs025_single | 5550 | 1.2 | +0.3 | – | 1.2 | – |
| knmi_harmonie_arome_europe | 5550 | 1.3 | +0.3 | 2.0 | 1.5 | 18 % |
| meteoswiss_icon_ch2 | 5550 | 1.3 | +0.5 | 2.1 | 1.4 | 18 % |
| dmi_harmonie_arome_europe | 5550 | 1.3 | +0.5 | 2.2 | 1.4 | 21 % |
| ecmwf_ifs025 | 5550 | 1.3 | +0.5 | 2.2 | 1.3 | 26 % |
| geosphere_arome_austria | 5550 | 1.3 | +0.4 | 2.0 | 2.2 | 15 % |
| meteoswiss_icon_ch1 | 1510 | 1.6 | +0.8 | 2.2 | 1.5 | 23 % |

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
| icon_eu | 4530 | 1700 | 1.33 | 1.04 | 22 % | 16 % |
| best_match | 4530 | 1700 | 1.39 | 1.09 | 21 % | 15 % |
| icon_d2 | 4530 | 1700 | 1.39 | 1.09 | 21 % | 15 % |
| ecmwf_aifs025_single | 4530 | 1700 | 1.44 | 1.13 | – | – |
| knmi_harmonie_arome_europe | 4530 | 1700 | 1.54 | 1.20 | 22 % | 14 % |
| ecmwf_ifs025 | 4530 | 1700 | 1.58 | 1.25 | 27 % | 20 % |
| dmi_harmonie_arome_europe | 4530 | 1700 | 1.59 | 1.24 | 26 % | 16 % |
| meteoswiss_icon_ch2 | 4530 | 1700 | 1.61 | 1.20 | 24 % | 16 % |
| meteoswiss_icon_ch1 | 4520 | 1690 | 1.75 | 1.32 | 25 % | 17 % |
| geosphere_arome_austria | 4530 | 1700 | 1.81 | 1.34 | 22 % | 14 % |

Same order of the models with one run a day: **no** (twice: icon_eu, best_match, icon_d2; once: icon_eu, icon_d2, best_match).

## icon_d2 vs best_match

126 forecast hours differ by more than wind 2.0 m/s, gusts 3.0 m/s or air 2.0 °C.

| Point | Hours |
| --- | --- |
| starnberger-see-south | 46 |
| staffelsee | 34 |
| starnberger-see-centre | 18 |
| tegernsee | 14 |
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
| best_match | 653 | 1.3 | +0.9 | 1.8 | 1.0 | 19 % |
| **icon_d2** (app today) | 653 | 1.3 | +0.9 | 1.8 | 1.0 | 19 % |
| icon_eu | 653 | 1.3 | +0.9 | 2.6 | 1.0 | 31 % |
| knmi_harmonie_arome_europe | 653 | 1.5 | +1.0 | 2.6 | 0.9 | 27 % |
| ecmwf_aifs025_single | 653 | 1.6 | +1.3 | – | 1.0 | – |
| meteoswiss_icon_ch2 | 653 | 1.6 | +1.4 | 2.1 | 1.1 | 20 % |
| dmi_harmonie_arome_europe | 653 | 1.7 | +1.3 | 2.4 | 1.0 | 27 % |
| meteoswiss_icon_ch1 | 652 | 1.7 | +1.4 | 2.7 | 1.1 | 27 % |
| geosphere_arome_austria | 653 | 1.8 | +1.5 | 2.5 | 1.5 | 21 % |
| ecmwf_ifs025 | 653 | 1.8 | +1.6 | 2.9 | 1.0 | 37 % |

### Tutzinger RV launch point

Stations: wind: Wielenbach (Demollstr.) (8.9 km), gust: Wielenbach (Demollstr.) (8.9 km), temp: Attenkam (6.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| **icon_d2** (app today) | 653 | 0.9 | +0.2 | 1.5 | 0.9 | 18 % |
| best_match | 653 | 0.9 | +0.2 | 1.5 | 0.9 | 18 % |
| icon_eu | 653 | 1.1 | +0.6 | 1.9 | 1.0 | 24 % |
| geosphere_arome_austria | 653 | 1.1 | +0.6 | 2.2 | 1.6 | 24 % |
| knmi_harmonie_arome_europe | 653 | 1.2 | +0.3 | 1.8 | 1.1 | 19 % |
| dmi_harmonie_arome_europe | 653 | 1.3 | +0.8 | 2.5 | 0.9 | 26 % |
| meteoswiss_icon_ch2 | 653 | 1.4 | +1.1 | 1.9 | 1.4 | 19 % |
| meteoswiss_icon_ch1 | 652 | 1.5 | +1.3 | 2.1 | 1.1 | 25 % |
| ecmwf_aifs025_single | 653 | 1.6 | +1.3 | – | 1.0 | – |
| ecmwf_ifs025 | 653 | 1.8 | +1.6 | 2.9 | 1.0 | 37 % |

### Starnberger See, centre

Stations: wind: Wielenbach (Demollstr.) (11.4 km), gust: Wielenbach (Demollstr.) (11.4 km), temp: Attenkam (5.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 653 | 1.3 | +0.9 | 1.6 | 1.0 | 20 % |
| **icon_d2** (app today) | 653 | 1.3 | +1.0 | 1.9 | 1.0 | 19 % |
| best_match | 653 | 1.3 | +1.0 | 1.9 | 1.0 | 19 % |
| ecmwf_aifs025_single | 653 | 1.6 | +1.3 | – | 1.0 | – |
| ecmwf_ifs025 | 653 | 1.8 | +1.6 | 2.9 | 1.0 | 37 % |
| knmi_harmonie_arome_europe | 653 | 1.8 | +1.6 | 2.8 | 1.0 | 28 % |
| meteoswiss_icon_ch2 | 653 | 1.8 | +1.7 | 2.8 | 1.4 | 28 % |
| dmi_harmonie_arome_europe | 653 | 2.1 | +2.0 | 3.4 | 1.1 | 36 % |
| geosphere_arome_austria | 653 | 2.2 | +2.1 | 2.4 | 1.6 | 24 % |
| meteoswiss_icon_ch1 | 652 | 2.8 | +2.8 | 2.6 | 1.9 | 28 % |

### Starnberger See, south near Seeshaupt

Stations: wind: Wielenbach (Demollstr.) (13.6 km), gust: Wielenbach (Demollstr.) (13.6 km), temp: Attenkam (5.6 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 653 | 0.9 | +0.0 | 1.5 | 1.0 | 20 % |
| **icon_d2** (app today) | 653 | 0.9 | -0.0 | 1.5 | 1.0 | 20 % |
| icon_eu | 653 | 0.9 | -0.1 | 1.7 | 1.1 | 21 % |
| knmi_harmonie_arome_europe | 653 | 1.2 | +0.2 | 1.9 | 1.0 | 19 % |
| meteoswiss_icon_ch1 | 652 | 1.2 | +0.7 | 1.9 | 1.2 | 20 % |
| dmi_harmonie_arome_europe | 653 | 1.2 | +0.6 | 2.1 | 1.0 | 22 % |
| ecmwf_aifs025_single | 653 | 1.2 | +0.2 | – | 0.9 | – |
| ecmwf_ifs025 | 653 | 1.4 | +0.6 | 2.4 | 1.2 | 31 % |
| geosphere_arome_austria | 653 | 1.7 | +1.4 | 1.9 | 1.8 | 20 % |
| meteoswiss_icon_ch2 | 653 | 1.7 | +1.6 | 2.3 | 1.7 | 27 % |

### Ammersee, centre

Stations: wind: Wielenbach (Demollstr.) (13.3 km), gust: Wielenbach (Demollstr.) (13.3 km), temp: Wielenbach (Demollstr.) (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 653 | 1.8 | +1.4 | 2.5 | 1.6 | 26 % |
| best_match | 653 | 1.8 | +1.4 | 2.2 | 1.6 | 22 % |
| **icon_d2** (app today) | 653 | 1.8 | +1.4 | 2.2 | 1.6 | 22 % |
| meteoswiss_icon_ch2 | 653 | 1.8 | +1.5 | 2.9 | 1.4 | 28 % |
| ecmwf_aifs025_single | 653 | 1.9 | +1.7 | – | 1.5 | – |
| dmi_harmonie_arome_europe | 653 | 2.0 | +1.7 | 4.3 | 1.7 | 42 % |
| ecmwf_ifs025 | 653 | 2.3 | +2.1 | 3.6 | 1.3 | 43 % |
| knmi_harmonie_arome_europe | 653 | 2.4 | +2.2 | 3.7 | 1.8 | 35 % |
| meteoswiss_icon_ch1 | 652 | 2.7 | +2.5 | 2.7 | 2.9 | 29 % |
| geosphere_arome_austria | 653 | 3.3 | +3.2 | 3.5 | 1.8 | 31 % |

### Wörthsee, centre

Stations: wind: Wielenbach (Demollstr.) (20.6 km), gust: Wielenbach (Demollstr.) (20.6 km), temp: Maisach-Galgen (15.7 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 653 | 1.6 | +1.3 | 2.1 | 1.2 | 22 % |
| **icon_d2** (app today) | 653 | 1.6 | +1.3 | 2.1 | 1.2 | 22 % |
| ecmwf_aifs025_single | 653 | 1.6 | +1.3 | – | 0.9 | – |
| icon_eu | 653 | 1.7 | +1.4 | 2.8 | 1.0 | 31 % |
| ecmwf_ifs025 | 653 | 1.8 | +1.6 | 2.9 | 1.0 | 37 % |
| knmi_harmonie_arome_europe | 653 | 1.8 | +1.6 | 2.8 | 0.8 | 27 % |
| meteoswiss_icon_ch2 | 653 | 2.0 | +1.9 | 2.9 | 0.8 | 29 % |
| geosphere_arome_austria | 653 | 2.2 | +1.9 | 3.4 | 1.1 | 29 % |
| meteoswiss_icon_ch1 | 652 | 2.2 | +2.1 | 3.1 | 0.9 | 28 % |
| dmi_harmonie_arome_europe | 653 | 2.3 | +2.1 | 3.0 | 0.9 | 31 % |

### Tegernsee, centre

Stations: wind: Kreuth (9.0 km), gust: Bichl (25.7 km), temp: Kreuth (9.0 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 653 | 1.1 | +0.8 | 5.0 | 1.1 | 43 % |
| ecmwf_aifs025_single | 653 | 1.2 | +1.0 | – | 1.6 | – |
| dmi_harmonie_arome_europe | 653 | 2.2 | +2.1 | 4.4 | 1.5 | 45 % |
| knmi_harmonie_arome_europe | 653 | 2.2 | +2.1 | 4.2 | 1.3 | 41 % |
| **icon_d2** (app today) | 653 | 2.2 | +2.1 | 7.0 | 1.4 | 65 % |
| best_match | 653 | 2.2 | +2.1 | 7.0 | 1.4 | 65 % |
| ecmwf_ifs025 | 653 | 2.3 | +2.1 | 3.4 | 1.9 | 38 % |
| geosphere_arome_austria | 653 | 2.4 | +2.0 | 3.9 | 2.1 | 38 % |
| meteoswiss_icon_ch2 | 653 | 2.6 | +2.5 | 6.9 | 1.4 | 65 % |
| meteoswiss_icon_ch1 | 652 | 2.9 | +2.7 | 7.3 | 1.4 | 64 % |

### Kochelsee, centre

Stations: wind: Bichl (8.9 km), gust: Bichl (8.9 km), temp: Bichl (8.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 653 | 1.0 | -0.3 | – | 1.2 | – |
| ecmwf_ifs025 | 653 | 1.0 | +0.1 | 1.8 | 1.4 | 20 % |
| meteoswiss_icon_ch2 | 653 | 1.1 | -0.3 | 2.1 | 1.8 | 20 % |
| knmi_harmonie_arome_europe | 653 | 1.2 | +0.0 | 1.9 | 1.4 | 22 % |
| best_match | 653 | 1.2 | -0.8 | 2.1 | 1.3 | 18 % |
| **icon_d2** (app today) | 653 | 1.2 | -0.8 | 2.1 | 1.4 | 18 % |
| geosphere_arome_austria | 653 | 1.2 | -0.3 | 2.4 | 2.0 | 27 % |
| dmi_harmonie_arome_europe | 653 | 1.2 | +0.2 | 2.1 | 1.3 | 29 % |
| meteoswiss_icon_ch1 | 652 | 1.3 | -0.4 | 2.2 | 1.3 | 27 % |
| icon_eu | 653 | 1.3 | -0.9 | 1.9 | 0.9 | 19 % |

### Staffelsee, centre

Stations: wind: Hohenpeißenberg (16.9 km), gust: Hohenpeißenberg (16.9 km), temp: Kohlgrub, Bad (Rosshof) (7.4 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| meteoswiss_icon_ch1 | 652 | 2.9 | -2.9 | 4.7 | 2.3 | 42 % |
| dmi_harmonie_arome_europe | 653 | 3.2 | -3.1 | 5.6 | 1.4 | 51 % |
| ecmwf_ifs025 | 653 | 3.3 | -3.3 | 5.2 | 1.2 | 51 % |
| geosphere_arome_austria | 653 | 3.4 | -3.4 | 5.7 | 2.0 | 51 % |
| meteoswiss_icon_ch2 | 653 | 3.5 | -3.5 | 5.7 | 2.4 | 50 % |
| knmi_harmonie_arome_europe | 653 | 3.5 | -3.4 | 5.6 | 1.4 | 49 % |
| ecmwf_aifs025_single | 653 | 3.7 | -3.7 | – | 1.0 | – |
| icon_eu | 653 | 3.9 | -3.9 | 7.0 | 1.4 | 55 % |
| **icon_d2** (app today) | 653 | 4.0 | -4.0 | 6.9 | 2.4 | 53 % |
| best_match | 653 | 4.0 | -4.0 | 6.9 | 2.4 | 53 % |

### Olympic regatta course Oberschleißheim

Stations: wind: München-Stadt (9.2 km), gust: München-Stadt (9.2 km), temp: München-Stadt (9.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 653 | 0.7 | -0.1 | 1.2 | 1.0 | 16 % |
| best_match | 653 | 0.7 | -0.1 | 1.2 | 1.0 | 19 % |
| **icon_d2** (app today) | 653 | 0.7 | -0.1 | 1.3 | 1.0 | 19 % |
| ecmwf_aifs025_single | 653 | 0.8 | +0.4 | – | 1.1 | – |
| meteoswiss_icon_ch2 | 653 | 0.8 | +0.3 | 1.4 | 1.2 | 21 % |
| ecmwf_ifs025 | 653 | 0.9 | +0.5 | 1.5 | 1.4 | 26 % |
| knmi_harmonie_arome_europe | 653 | 0.9 | +0.3 | 1.6 | 1.3 | 24 % |
| meteoswiss_icon_ch1 | 652 | 0.9 | +0.6 | 1.6 | 1.1 | 26 % |
| dmi_harmonie_arome_europe | 653 | 0.9 | +0.4 | 1.6 | 1.3 | 27 % |
| geosphere_arome_austria | 653 | 1.3 | +1.0 | 1.8 | 1.9 | 25 % |

Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0).
