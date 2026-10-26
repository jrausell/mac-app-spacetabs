#!/bin/zsh
set -eu
cd "${0:A:h:h}"
xcrun swift-format format --configuration .swift-format --in-place --recursive Sources Tests Scripts/build-icons.swift Package.swift
