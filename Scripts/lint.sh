#!/bin/zsh
set -eu
cd "${0:A:h:h}"
xcrun swift-format lint --configuration .swift-format --strict --recursive Sources Tests Tools Scripts/build-icons.swift Package.swift
