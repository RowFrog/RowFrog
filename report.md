# Model check, 2026-11-05 05:37 UTC

39 forecast runs stored (2026-10-23T20:00Z to 2026-11-05T05:00Z).
Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.
"Light wrong" = how often wind and gusts alone would have given a different rowing light than measured.
Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.

## All points, day 1

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 9050 | 1.3 | +0.0 | 2.5 | 1.1 | 27 % |
| best_match | 9050 | 1.4 | +0.1 | 2.6 | 1.3 | 27 % |
| **icon_d2** (app today) | 9050 | 1.4 | +0.1 | 2.6 | 1.3 | 27 % |
| ecmwf_aifs025_single | 9050 | 1.4 | +0.3 | – | 1.1 | – |
| knmi_harmonie_arome_europe | 9050 | 1.6 | +0.4 | 2.6 | 1.2 | 27 % |
| ecmwf_ifs025 | 9050 | 1.6 | +0.7 | 2.6 | 1.2 | 33 % |
| meteoswiss_icon_ch2 | 9050 | 1.6 | +0.7 | 2.8 | 1.4 | 29 % |
| dmi_harmonie_arome_europe | 9050 | 1.6 | +0.6 | 2.8 | 1.2 | 31 % |
| meteoswiss_icon_ch1 | 9040 | 1.8 | +1.0 | 2.8 | 1.5 | 31 % |
| geosphere_arome_austria | 9050 | 1.8 | +0.7 | 2.7 | 1.7 | 27 % |

## All points, day 2

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 7850 | 1.0 | -0.2 | 2.0 | 1.0 | 18 % |
| best_match | 7850 | 1.1 | -0.1 | 2.1 | 1.3 | 20 % |
| **icon_d2** (app today) | 7540 | 1.1 | -0.0 | 2.1 | 1.2 | 20 % |
| ecmwf_aifs025_single | 7850 | 1.1 | +0.2 | – | 1.2 | – |
| meteoswiss_icon_ch2 | 7850 | 1.2 | +0.4 | 2.1 | 1.4 | 20 % |
| ecmwf_ifs025 | 7850 | 1.2 | +0.5 | 2.0 | 1.2 | 26 % |
| knmi_harmonie_arome_europe | 7850 | 1.2 | +0.2 | 2.0 | 1.4 | 19 % |
| dmi_harmonie_arome_europe | 7850 | 1.3 | +0.3 | 2.2 | 1.4 | 22 % |
| geosphere_arome_austria | 7850 | 1.3 | +0.3 | 2.0 | 2.0 | 17 % |
| meteoswiss_icon_ch1 | 2210 | 1.5 | +0.8 | 2.2 | 1.5 | 25 % |

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
| icon_eu | 7030 | 2950 | 1.18 | 0.98 | 22 % | 19 % |
| best_match | 7030 | 2950 | 1.26 | 1.06 | 23 % | 20 % |
| icon_d2 | 7030 | 2950 | 1.26 | 1.06 | 23 % | 20 % |
| ecmwf_aifs025_single | 7030 | 2950 | 1.27 | 1.06 | – | – |
| knmi_harmonie_arome_europe | 7030 | 2950 | 1.38 | 1.16 | 22 % | 18 % |
| ecmwf_ifs025 | 7030 | 2950 | 1.39 | 1.17 | 26 % | 22 % |
| meteoswiss_icon_ch2 | 7030 | 2950 | 1.42 | 1.14 | 24 % | 20 % |
| dmi_harmonie_arome_europe | 7030 | 2950 | 1.43 | 1.19 | 25 % | 20 % |
| meteoswiss_icon_ch1 | 7020 | 2940 | 1.59 | 1.33 | 26 % | 22 % |
| geosphere_arome_austria | 7030 | 2950 | 1.59 | 1.26 | 22 % | 17 % |

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
| icon_eu | 905 | 1.1 | +0.6 | 2.3 | 0.9 | 30 % |
| best_match | 905 | 1.2 | +0.6 | 1.7 | 1.0 | 20 % |
| **icon_d2** (app today) | 905 | 1.2 | +0.6 | 1.7 | 1.0 | 20 % |
| knmi_harmonie_arome_europe | 905 | 1.3 | +0.6 | 2.2 | 0.9 | 25 % |
| meteoswiss_icon_ch2 | 905 | 1.4 | +1.1 | 1.8 | 1.0 | 20 % |
| ecmwf_aifs025_single | 905 | 1.4 | +1.0 | – | 1.0 | – |
| meteoswiss_icon_ch1 | 904 | 1.4 | +1.1 | 2.3 | 1.1 | 25 % |
| dmi_harmonie_arome_europe | 905 | 1.4 | +1.0 | 2.1 | 1.0 | 25 % |
| geosphere_arome_austria | 905 | 1.5 | +1.0 | 2.2 | 1.3 | 22 % |
| ecmwf_ifs025 | 905 | 1.5 | +1.3 | 2.6 | 1.0 | 35 % |

### Tutzinger RV launch point

Stations: wind: Wielenbach (Demollstr.) (8.9 km), gust: Wielenbach (Demollstr.) (8.9 km), temp: Attenkam (6.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 905 | 0.9 | +0.2 | 1.5 | 1.0 | 19 % |
| **icon_d2** (app today) | 905 | 0.9 | +0.2 | 1.5 | 1.0 | 19 % |
| icon_eu | 905 | 1.0 | +0.5 | 1.8 | 1.0 | 25 % |
| geosphere_arome_austria | 905 | 1.1 | +0.5 | 2.0 | 1.4 | 23 % |
| knmi_harmonie_arome_europe | 905 | 1.1 | +0.2 | 1.7 | 1.0 | 20 % |
| dmi_harmonie_arome_europe | 905 | 1.2 | +0.7 | 2.3 | 0.9 | 24 % |
| meteoswiss_icon_ch2 | 905 | 1.4 | +1.2 | 1.8 | 1.5 | 21 % |
| ecmwf_aifs025_single | 905 | 1.4 | +1.0 | – | 1.0 | – |
| ecmwf_ifs025 | 905 | 1.5 | +1.3 | 2.6 | 1.0 | 35 % |
| meteoswiss_icon_ch1 | 904 | 1.6 | +1.5 | 2.3 | 1.3 | 29 % |

### Starnberger See, centre

Stations: wind: Wielenbach (Demollstr.) (11.4 km), gust: Wielenbach (Demollstr.) (11.4 km), temp: Attenkam (5.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| **icon_d2** (app today) | 905 | 1.2 | +0.8 | 1.8 | 1.0 | 20 % |
| best_match | 905 | 1.2 | +0.8 | 1.8 | 1.0 | 20 % |
| icon_eu | 905 | 1.2 | +0.9 | 1.5 | 1.1 | 20 % |
| ecmwf_aifs025_single | 905 | 1.4 | +1.0 | – | 1.0 | – |
| ecmwf_ifs025 | 905 | 1.5 | +1.3 | 2.6 | 1.0 | 35 % |
| knmi_harmonie_arome_europe | 905 | 1.5 | +1.3 | 2.5 | 1.0 | 26 % |
| meteoswiss_icon_ch2 | 905 | 1.6 | +1.5 | 2.5 | 1.3 | 26 % |
| dmi_harmonie_arome_europe | 905 | 1.8 | +1.6 | 3.0 | 1.0 | 32 % |
| geosphere_arome_austria | 905 | 2.0 | +1.9 | 2.2 | 1.5 | 24 % |
| meteoswiss_icon_ch1 | 904 | 2.6 | +2.5 | 2.3 | 1.9 | 27 % |

### Starnberger See, south near Seeshaupt

Stations: wind: Wielenbach (Demollstr.) (13.6 km), gust: Wielenbach (Demollstr.) (13.6 km), temp: Attenkam (5.6 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 905 | 0.9 | -0.2 | 1.5 | 1.0 | 21 % |
| best_match | 905 | 0.9 | -0.1 | 1.5 | 1.1 | 21 % |
| **icon_d2** (app today) | 905 | 0.9 | -0.1 | 1.5 | 1.1 | 21 % |
| meteoswiss_icon_ch1 | 904 | 1.1 | +0.5 | 1.7 | 1.2 | 21 % |
| knmi_harmonie_arome_europe | 905 | 1.1 | -0.0 | 1.7 | 1.0 | 20 % |
| dmi_harmonie_arome_europe | 905 | 1.2 | +0.3 | 2.0 | 1.0 | 22 % |
| ecmwf_ifs025 | 905 | 1.2 | +0.4 | 2.1 | 1.1 | 29 % |
| ecmwf_aifs025_single | 905 | 1.2 | -0.1 | – | 0.9 | – |
| geosphere_arome_austria | 905 | 1.5 | +1.0 | 1.8 | 1.6 | 21 % |
| meteoswiss_icon_ch2 | 905 | 1.5 | +1.4 | 2.1 | 1.6 | 25 % |

### Ammersee, centre

Stations: wind: Wielenbach (Demollstr.) (13.3 km), gust: Wielenbach (Demollstr.) (13.3 km), temp: Wielenbach (Demollstr.) (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 905 | 1.5 | +1.1 | 2.1 | 1.4 | 24 % |
| best_match | 905 | 1.5 | +1.1 | 2.0 | 1.4 | 23 % |
| **icon_d2** (app today) | 905 | 1.5 | +1.1 | 2.0 | 1.4 | 23 % |
| meteoswiss_icon_ch2 | 905 | 1.5 | +1.2 | 2.4 | 1.3 | 25 % |
| ecmwf_aifs025_single | 905 | 1.6 | +1.3 | – | 1.4 | – |
| dmi_harmonie_arome_europe | 905 | 1.8 | +1.2 | 3.6 | 1.5 | 36 % |
| ecmwf_ifs025 | 905 | 1.9 | +1.8 | 3.1 | 1.3 | 39 % |
| knmi_harmonie_arome_europe | 905 | 2.0 | +1.7 | 3.1 | 1.6 | 30 % |
| meteoswiss_icon_ch1 | 904 | 2.3 | +2.1 | 2.4 | 2.9 | 27 % |
| geosphere_arome_austria | 905 | 2.7 | +2.4 | 3.0 | 1.7 | 29 % |

### Wörthsee, centre

Stations: wind: Wielenbach (Demollstr.) (20.6 km), gust: Wielenbach (Demollstr.) (20.6 km), temp: Maisach-Galgen (15.7 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 905 | 1.4 | +1.0 | 1.9 | 1.1 | 22 % |
| **icon_d2** (app today) | 905 | 1.4 | +1.0 | 1.9 | 1.1 | 22 % |
| ecmwf_aifs025_single | 905 | 1.4 | +1.0 | – | 0.8 | – |
| icon_eu | 905 | 1.5 | +1.1 | 2.4 | 0.9 | 29 % |
| ecmwf_ifs025 | 905 | 1.5 | +1.3 | 2.6 | 0.9 | 35 % |
| knmi_harmonie_arome_europe | 905 | 1.6 | +1.2 | 2.4 | 0.8 | 25 % |
| meteoswiss_icon_ch2 | 905 | 1.7 | +1.6 | 2.5 | 0.8 | 27 % |
| geosphere_arome_austria | 905 | 1.8 | +1.4 | 2.8 | 1.2 | 26 % |
| dmi_harmonie_arome_europe | 905 | 1.9 | +1.7 | 2.6 | 0.8 | 28 % |
| meteoswiss_icon_ch1 | 904 | 2.0 | +1.9 | 2.8 | 0.9 | 29 % |

### Tegernsee, centre

Stations: wind: Kreuth (9.0 km), gust: Bichl (25.7 km), temp: Kreuth (9.0 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 905 | 1.0 | +0.8 | 4.2 | 1.3 | 32 % |
| ecmwf_aifs025_single | 905 | 1.2 | +1.0 | – | 1.6 | – |
| knmi_harmonie_arome_europe | 905 | 2.1 | +2.1 | 3.9 | 1.7 | 37 % |
| ecmwf_ifs025 | 905 | 2.1 | +2.0 | 2.9 | 2.1 | 31 % |
| **icon_d2** (app today) | 905 | 2.1 | +2.0 | 6.3 | 1.6 | 64 % |
| best_match | 905 | 2.1 | +2.0 | 6.3 | 1.6 | 64 % |
| dmi_harmonie_arome_europe | 905 | 2.2 | +2.1 | 4.2 | 1.9 | 46 % |
| geosphere_arome_austria | 905 | 2.3 | +2.0 | 3.4 | 2.5 | 29 % |
| meteoswiss_icon_ch2 | 905 | 2.4 | +2.3 | 6.3 | 1.6 | 64 % |
| meteoswiss_icon_ch1 | 904 | 2.7 | +2.6 | 6.8 | 1.7 | 65 % |

### Kochelsee, centre

Stations: wind: Bichl (8.9 km), gust: Bichl (8.9 km), temp: Bichl (8.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 905 | 0.9 | -0.1 | – | 1.1 | – |
| meteoswiss_icon_ch2 | 905 | 1.0 | -0.3 | 2.0 | 1.6 | 15 % |
| ecmwf_ifs025 | 905 | 1.0 | +0.4 | 1.8 | 1.2 | 20 % |
| best_match | 905 | 1.1 | -0.6 | 2.0 | 1.3 | 14 % |
| **icon_d2** (app today) | 905 | 1.1 | -0.6 | 2.0 | 1.3 | 14 % |
| knmi_harmonie_arome_europe | 905 | 1.1 | +0.1 | 1.8 | 1.5 | 19 % |
| icon_eu | 905 | 1.2 | -0.9 | 1.8 | 0.9 | 15 % |
| geosphere_arome_austria | 905 | 1.2 | -0.4 | 2.4 | 1.9 | 21 % |
| meteoswiss_icon_ch1 | 904 | 1.2 | -0.4 | 2.1 | 1.2 | 20 % |
| dmi_harmonie_arome_europe | 905 | 1.2 | +0.1 | 2.1 | 1.4 | 23 % |

### Staffelsee, centre

Stations: wind: Hohenpeißenberg (16.9 km), gust: Hohenpeißenberg (16.9 km), temp: Kohlgrub, Bad (Rosshof) (7.4 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| meteoswiss_icon_ch1 | 904 | 2.5 | -2.4 | 4.0 | 2.0 | 39 % |
| dmi_harmonie_arome_europe | 905 | 2.8 | -2.7 | 4.9 | 1.4 | 49 % |
| ecmwf_ifs025 | 905 | 2.8 | -2.8 | 4.3 | 1.1 | 46 % |
| meteoswiss_icon_ch2 | 905 | 2.9 | -2.9 | 4.8 | 2.1 | 46 % |
| knmi_harmonie_arome_europe | 905 | 3.1 | -3.0 | 5.0 | 1.3 | 48 % |
| geosphere_arome_austria | 905 | 3.1 | -3.1 | 5.1 | 1.8 | 49 % |
| ecmwf_aifs025_single | 905 | 3.3 | -3.3 | – | 0.9 | – |
| best_match | 905 | 3.4 | -3.4 | 5.8 | 2.1 | 51 % |
| **icon_d2** (app today) | 905 | 3.4 | -3.4 | 5.8 | 2.1 | 51 % |
| icon_eu | 905 | 3.5 | -3.5 | 6.3 | 1.2 | 53 % |

### Olympic regatta course Oberschleißheim

Stations: wind: München-Stadt (9.2 km), gust: München-Stadt (9.2 km), temp: München-Stadt (9.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 905 | 0.7 | -0.2 | 1.2 | 0.9 | 17 % |
| best_match | 905 | 0.7 | -0.2 | 1.2 | 1.0 | 19 % |
| **icon_d2** (app today) | 905 | 0.7 | -0.2 | 1.2 | 1.0 | 19 % |
| ecmwf_aifs025_single | 905 | 0.7 | +0.4 | – | 1.0 | – |
| meteoswiss_icon_ch2 | 905 | 0.8 | +0.3 | 1.3 | 1.1 | 21 % |
| knmi_harmonie_arome_europe | 905 | 0.8 | +0.2 | 1.4 | 1.2 | 23 % |
| ecmwf_ifs025 | 905 | 0.8 | +0.4 | 1.3 | 1.2 | 24 % |
| dmi_harmonie_arome_europe | 905 | 0.8 | +0.3 | 1.5 | 1.2 | 24 % |
| meteoswiss_icon_ch1 | 904 | 0.8 | +0.5 | 1.4 | 1.0 | 24 % |
| geosphere_arome_austria | 905 | 1.2 | +0.7 | 1.7 | 1.9 | 23 % |

Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0).
