# Model check, 2026-11-06 05:37 UTC

41 forecast runs stored (2026-10-23T20:00Z to 2026-11-06T05:00Z).
Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.
"Light wrong" = how often wind and gusts alone would have given a different rowing light than measured.
Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.

## All points, day 1

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 9780 | 1.3 | +0.1 | 2.4 | 1.1 | 25 % |
| best_match | 9780 | 1.4 | +0.1 | 2.5 | 1.3 | 25 % |
| **icon_d2** (app today) | 9780 | 1.4 | +0.1 | 2.5 | 1.3 | 25 % |
| ecmwf_aifs025_single | 9780 | 1.4 | +0.3 | – | 1.1 | – |
| knmi_harmonie_arome_europe | 9780 | 1.5 | +0.4 | 2.5 | 1.3 | 25 % |
| ecmwf_ifs025 | 9780 | 1.5 | +0.7 | 2.5 | 1.2 | 30 % |
| meteoswiss_icon_ch2 | 9780 | 1.6 | +0.7 | 2.6 | 1.4 | 27 % |
| dmi_harmonie_arome_europe | 9780 | 1.6 | +0.6 | 2.7 | 1.3 | 29 % |
| meteoswiss_icon_ch1 | 9770 | 1.7 | +0.9 | 2.7 | 1.6 | 28 % |
| geosphere_arome_austria | 9780 | 1.8 | +0.7 | 2.6 | 1.7 | 25 % |

## All points, day 2

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 8320 | 1.0 | -0.2 | 2.0 | 1.1 | 17 % |
| best_match | 8320 | 1.1 | -0.1 | 2.0 | 1.3 | 19 % |
| **icon_d2** (app today) | 7990 | 1.1 | -0.0 | 2.0 | 1.3 | 19 % |
| ecmwf_aifs025_single | 8320 | 1.1 | +0.2 | – | 1.2 | – |
| meteoswiss_icon_ch2 | 8320 | 1.2 | +0.4 | 2.0 | 1.4 | 19 % |
| ecmwf_ifs025 | 8320 | 1.2 | +0.4 | 2.0 | 1.2 | 24 % |
| knmi_harmonie_arome_europe | 8320 | 1.2 | +0.2 | 2.0 | 1.5 | 18 % |
| dmi_harmonie_arome_europe | 8320 | 1.3 | +0.4 | 2.2 | 1.4 | 21 % |
| geosphere_arome_austria | 8320 | 1.3 | +0.3 | 2.0 | 2.0 | 16 % |
| meteoswiss_icon_ch1 | 2360 | 1.4 | +0.7 | 2.2 | 1.5 | 23 % |

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
| icon_eu | 7530 | 3200 | 1.15 | 0.96 | 20 % | 17 % |
| best_match | 7530 | 3200 | 1.22 | 1.03 | 22 % | 18 % |
| icon_d2 | 7530 | 3200 | 1.22 | 1.03 | 22 % | 18 % |
| ecmwf_aifs025_single | 7530 | 3200 | 1.23 | 1.03 | – | – |
| knmi_harmonie_arome_europe | 7530 | 3200 | 1.34 | 1.13 | 21 % | 16 % |
| ecmwf_ifs025 | 7530 | 3200 | 1.34 | 1.13 | 24 % | 21 % |
| meteoswiss_icon_ch2 | 7530 | 3200 | 1.37 | 1.10 | 23 % | 18 % |
| dmi_harmonie_arome_europe | 7530 | 3200 | 1.39 | 1.17 | 23 % | 18 % |
| meteoswiss_icon_ch1 | 7520 | 3190 | 1.53 | 1.28 | 24 % | 20 % |
| geosphere_arome_austria | 7530 | 3200 | 1.55 | 1.23 | 21 % | 16 % |

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
| icon_eu | 978 | 1.1 | +0.6 | 2.3 | 0.9 | 28 % |
| best_match | 978 | 1.1 | +0.5 | 1.6 | 1.1 | 18 % |
| **icon_d2** (app today) | 978 | 1.1 | +0.5 | 1.6 | 1.1 | 18 % |
| knmi_harmonie_arome_europe | 978 | 1.3 | +0.6 | 2.1 | 1.0 | 23 % |
| meteoswiss_icon_ch2 | 978 | 1.3 | +1.0 | 1.8 | 1.1 | 19 % |
| ecmwf_aifs025_single | 978 | 1.3 | +1.0 | – | 1.0 | – |
| meteoswiss_icon_ch1 | 977 | 1.4 | +1.0 | 2.2 | 1.1 | 23 % |
| dmi_harmonie_arome_europe | 978 | 1.4 | +0.9 | 2.1 | 1.1 | 23 % |
| geosphere_arome_austria | 978 | 1.5 | +1.0 | 2.1 | 1.3 | 20 % |
| ecmwf_ifs025 | 978 | 1.5 | +1.3 | 2.5 | 1.0 | 32 % |

### Tutzinger RV launch point

Stations: wind: Wielenbach (Demollstr.) (8.9 km), gust: Wielenbach (Demollstr.) (8.9 km), temp: Attenkam (6.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 978 | 0.9 | +0.2 | 1.4 | 1.1 | 17 % |
| **icon_d2** (app today) | 978 | 0.9 | +0.2 | 1.4 | 1.1 | 17 % |
| icon_eu | 978 | 0.9 | +0.5 | 1.8 | 1.0 | 24 % |
| geosphere_arome_austria | 978 | 1.0 | +0.5 | 2.0 | 1.4 | 21 % |
| knmi_harmonie_arome_europe | 978 | 1.1 | +0.2 | 1.6 | 1.2 | 18 % |
| dmi_harmonie_arome_europe | 978 | 1.2 | +0.6 | 2.2 | 1.1 | 22 % |
| meteoswiss_icon_ch2 | 978 | 1.3 | +1.1 | 1.8 | 1.5 | 20 % |
| ecmwf_aifs025_single | 978 | 1.3 | +1.0 | – | 1.0 | – |
| ecmwf_ifs025 | 978 | 1.5 | +1.3 | 2.5 | 1.0 | 32 % |
| meteoswiss_icon_ch1 | 977 | 1.6 | +1.4 | 2.2 | 1.4 | 27 % |

### Starnberger See, centre

Stations: wind: Wielenbach (Demollstr.) (11.4 km), gust: Wielenbach (Demollstr.) (11.4 km), temp: Attenkam (5.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| **icon_d2** (app today) | 978 | 1.1 | +0.8 | 1.7 | 1.1 | 18 % |
| best_match | 978 | 1.1 | +0.8 | 1.7 | 1.1 | 18 % |
| icon_eu | 978 | 1.1 | +0.9 | 1.4 | 1.1 | 18 % |
| ecmwf_aifs025_single | 978 | 1.3 | +1.0 | – | 1.0 | – |
| ecmwf_ifs025 | 978 | 1.5 | +1.3 | 2.5 | 1.0 | 32 % |
| knmi_harmonie_arome_europe | 978 | 1.5 | +1.2 | 2.4 | 1.2 | 24 % |
| meteoswiss_icon_ch2 | 978 | 1.5 | +1.4 | 2.3 | 1.4 | 24 % |
| dmi_harmonie_arome_europe | 978 | 1.7 | +1.6 | 2.9 | 1.2 | 30 % |
| geosphere_arome_austria | 978 | 1.9 | +1.8 | 2.1 | 1.5 | 22 % |
| meteoswiss_icon_ch1 | 977 | 2.4 | +2.3 | 2.2 | 2.0 | 25 % |

### Starnberger See, south near Seeshaupt

Stations: wind: Wielenbach (Demollstr.) (13.6 km), gust: Wielenbach (Demollstr.) (13.6 km), temp: Attenkam (5.6 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 978 | 0.8 | -0.2 | 1.5 | 1.0 | 20 % |
| best_match | 978 | 0.9 | -0.1 | 1.4 | 1.2 | 19 % |
| **icon_d2** (app today) | 978 | 0.9 | -0.1 | 1.4 | 1.2 | 19 % |
| meteoswiss_icon_ch1 | 977 | 1.0 | +0.4 | 1.7 | 1.3 | 20 % |
| knmi_harmonie_arome_europe | 978 | 1.1 | -0.0 | 1.7 | 1.1 | 19 % |
| dmi_harmonie_arome_europe | 978 | 1.1 | +0.4 | 1.9 | 1.1 | 20 % |
| ecmwf_ifs025 | 978 | 1.2 | +0.3 | 2.0 | 1.1 | 27 % |
| ecmwf_aifs025_single | 978 | 1.2 | -0.1 | – | 1.0 | – |
| geosphere_arome_austria | 978 | 1.4 | +1.0 | 1.8 | 1.6 | 20 % |
| meteoswiss_icon_ch2 | 978 | 1.5 | +1.3 | 2.0 | 1.7 | 23 % |

### Ammersee, centre

Stations: wind: Wielenbach (Demollstr.) (13.3 km), gust: Wielenbach (Demollstr.) (13.3 km), temp: Wielenbach (Demollstr.) (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 978 | 1.4 | +1.1 | 2.0 | 1.4 | 22 % |
| meteoswiss_icon_ch2 | 978 | 1.4 | +1.1 | 2.3 | 1.3 | 23 % |
| best_match | 978 | 1.4 | +1.0 | 1.9 | 1.4 | 21 % |
| **icon_d2** (app today) | 978 | 1.4 | +1.0 | 1.9 | 1.4 | 21 % |
| ecmwf_aifs025_single | 978 | 1.5 | +1.3 | – | 1.4 | – |
| dmi_harmonie_arome_europe | 978 | 1.7 | +1.1 | 3.4 | 1.6 | 33 % |
| ecmwf_ifs025 | 978 | 1.8 | +1.7 | 3.0 | 1.3 | 36 % |
| knmi_harmonie_arome_europe | 978 | 1.9 | +1.6 | 2.9 | 1.6 | 28 % |
| meteoswiss_icon_ch1 | 977 | 2.2 | +2.0 | 2.3 | 3.0 | 25 % |
| geosphere_arome_austria | 978 | 2.5 | +2.2 | 2.9 | 1.7 | 27 % |

### Wörthsee, centre

Stations: wind: Wielenbach (Demollstr.) (20.6 km), gust: Wielenbach (Demollstr.) (20.6 km), temp: Maisach-Galgen (15.7 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 978 | 1.3 | +1.0 | – | 0.9 | – |
| best_match | 978 | 1.3 | +1.0 | 1.8 | 1.2 | 20 % |
| **icon_d2** (app today) | 978 | 1.3 | +1.0 | 1.8 | 1.2 | 20 % |
| icon_eu | 978 | 1.4 | +1.1 | 2.4 | 0.9 | 27 % |
| ecmwf_ifs025 | 978 | 1.5 | +1.3 | 2.5 | 1.0 | 32 % |
| knmi_harmonie_arome_europe | 978 | 1.5 | +1.2 | 2.3 | 0.9 | 23 % |
| meteoswiss_icon_ch2 | 978 | 1.7 | +1.5 | 2.4 | 0.9 | 25 % |
| geosphere_arome_austria | 978 | 1.7 | +1.4 | 2.7 | 1.2 | 24 % |
| dmi_harmonie_arome_europe | 978 | 1.9 | +1.7 | 2.5 | 1.0 | 26 % |
| meteoswiss_icon_ch1 | 977 | 1.9 | +1.8 | 2.7 | 1.0 | 27 % |

### Tegernsee, centre

Stations: wind: Kreuth (9.0 km), gust: Bichl (25.7 km), temp: Kreuth (9.0 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 978 | 1.0 | +0.7 | 4.1 | 1.3 | 30 % |
| ecmwf_aifs025_single | 978 | 1.1 | +0.9 | – | 1.7 | – |
| knmi_harmonie_arome_europe | 978 | 2.0 | +1.9 | 3.7 | 1.7 | 34 % |
| ecmwf_ifs025 | 978 | 2.0 | +1.9 | 2.8 | 2.1 | 29 % |
| **icon_d2** (app today) | 978 | 2.0 | +1.9 | 6.0 | 1.7 | 59 % |
| best_match | 978 | 2.0 | +1.9 | 6.0 | 1.7 | 59 % |
| dmi_harmonie_arome_europe | 978 | 2.1 | +2.0 | 4.1 | 1.9 | 43 % |
| geosphere_arome_austria | 978 | 2.2 | +1.8 | 3.2 | 2.4 | 27 % |
| meteoswiss_icon_ch2 | 978 | 2.3 | +2.1 | 6.0 | 1.7 | 59 % |
| meteoswiss_icon_ch1 | 977 | 2.6 | +2.4 | 6.4 | 1.7 | 60 % |

### Kochelsee, centre

Stations: wind: Bichl (8.9 km), gust: Bichl (8.9 km), temp: Bichl (8.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 978 | 0.8 | -0.1 | – | 1.1 | – |
| ecmwf_ifs025 | 978 | 1.0 | +0.3 | 1.8 | 1.2 | 19 % |
| meteoswiss_icon_ch2 | 978 | 1.0 | -0.3 | 1.9 | 1.6 | 14 % |
| knmi_harmonie_arome_europe | 978 | 1.1 | +0.1 | 1.7 | 1.6 | 18 % |
| best_match | 978 | 1.1 | -0.5 | 1.9 | 1.3 | 13 % |
| **icon_d2** (app today) | 978 | 1.1 | -0.5 | 1.9 | 1.3 | 13 % |
| icon_eu | 978 | 1.1 | -0.8 | 1.8 | 0.9 | 14 % |
| geosphere_arome_austria | 978 | 1.1 | -0.4 | 2.3 | 2.0 | 19 % |
| meteoswiss_icon_ch1 | 977 | 1.1 | -0.4 | 2.0 | 1.2 | 19 % |
| dmi_harmonie_arome_europe | 978 | 1.2 | +0.1 | 2.0 | 1.5 | 21 % |

### Staffelsee, centre

Stations: wind: Hohenpeißenberg (16.9 km), gust: Hohenpeißenberg (16.9 km), temp: Kohlgrub, Bad (Rosshof) (7.4 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| meteoswiss_icon_ch1 | 977 | 2.3 | -2.2 | 3.8 | 2.0 | 36 % |
| dmi_harmonie_arome_europe | 978 | 2.6 | -2.5 | 4.7 | 1.5 | 46 % |
| ecmwf_ifs025 | 978 | 2.7 | -2.6 | 4.1 | 1.1 | 43 % |
| meteoswiss_icon_ch2 | 978 | 2.8 | -2.7 | 4.6 | 2.1 | 42 % |
| knmi_harmonie_arome_europe | 978 | 2.9 | -2.8 | 4.8 | 1.5 | 44 % |
| geosphere_arome_austria | 978 | 3.0 | -2.9 | 4.9 | 1.8 | 46 % |
| ecmwf_aifs025_single | 978 | 3.1 | -3.1 | – | 1.0 | – |
| best_match | 978 | 3.2 | -3.2 | 5.5 | 2.1 | 47 % |
| **icon_d2** (app today) | 978 | 3.2 | -3.2 | 5.5 | 2.1 | 47 % |
| icon_eu | 978 | 3.2 | -3.2 | 6.0 | 1.2 | 49 % |

### Olympic regatta course Oberschleißheim

Stations: wind: München-Stadt (9.2 km), gust: München-Stadt (9.2 km), temp: München-Stadt (9.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 978 | 0.7 | -0.2 | 1.2 | 1.0 | 18 % |
| **icon_d2** (app today) | 978 | 0.7 | -0.2 | 1.2 | 1.0 | 18 % |
| icon_eu | 978 | 0.7 | -0.1 | 1.3 | 0.9 | 16 % |
| ecmwf_aifs025_single | 978 | 0.7 | +0.4 | – | 1.0 | – |
| meteoswiss_icon_ch2 | 978 | 0.8 | +0.3 | 1.3 | 1.1 | 19 % |
| knmi_harmonie_arome_europe | 978 | 0.8 | +0.2 | 1.5 | 1.3 | 21 % |
| ecmwf_ifs025 | 978 | 0.8 | +0.4 | 1.4 | 1.3 | 22 % |
| dmi_harmonie_arome_europe | 978 | 0.8 | +0.3 | 1.5 | 1.3 | 22 % |
| meteoswiss_icon_ch1 | 977 | 0.8 | +0.4 | 1.4 | 1.1 | 22 % |
| geosphere_arome_austria | 978 | 1.1 | +0.7 | 1.7 | 1.9 | 22 % |

Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0).
