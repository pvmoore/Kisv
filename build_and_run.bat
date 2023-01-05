@echo off
chcp 65001

echo dub run --build=debug --config=%1 --compiler=dmd --arch=x86_64 --parallel -- %2 %3 %4 %5

dub run --build=debug --config=%1 --compiler=dmd --arch=x86_64 --parallel -- %2 %3 %4 %5