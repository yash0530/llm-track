.PHONY: build run app start stop restart dump clean

build:
	swift build

run: build
	./.build/debug/LLMTrack

app:
	bash Scripts/build_app.sh

start: app
	open build/LLMTrack.app

stop:
	killall LLMTrack 2>/dev/null || true

restart: stop app
	open build/LLMTrack.app

dump: build
	./.build/debug/LLMTrack --dump

clean:
	rm -rf .build build
