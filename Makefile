.PHONY: build run app dump clean

build:
	swift build

run: build
	./.build/debug/LLMTrack

app:
	bash Scripts/build_app.sh

dump: build
	./.build/debug/LLMTrack --dump

clean:
	rm -rf .build build
