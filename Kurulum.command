#!/usr/bin/env bash
cd "$(dirname "$0")"
if [ -f "./install.sh" ]; then
    bash ./install.sh
else
    curl -fsSL https://raw.githubusercontent.com/ssayoglu/mandalina-udf-converter/main/install.sh | bash
fi
