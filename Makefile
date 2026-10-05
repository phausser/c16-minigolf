ACME ?= acme
VICE ?= xplus4
PYTHON ?= python3
TEST_PYTHON ?= .venv/bin/python
# Leer: Joystick-Einstellung aus der eigenen vicerc. Sonst VICE-Gerät,
# z. B. 1 = Ziffernblock, 2 = Tastensatz 1, 4 = erster Host-Joystick.
JOYDEV ?=

PRG := build/minigolf.prg
# Same kernel with only the hardware test course: tests, smoke and profiles.
TEST_PRG := build/minigolf-test.prg
SOURCES := $(wildcard src/*.asm src/*.inc)
COURSES := $(wildcard assets/courses/*.json)
ACMEFLAGS := --cpu 6502 --format cbm --strict-segments

.PHONY: all run play editor test smoke budget benchmark profile preview screenshot check clean
all: $(PRG) $(TEST_PRG)

build:
	mkdir -p build

build/assets.inc: tools/generate_assets.py tools/course_codec.py tests/course_reference.py $(COURSES) | build
	$(PYTHON) tools/generate_assets.py

build/assets-test.inc: tools/generate_assets.py tools/course_codec.py tests/course_reference.py assets/test-course.json | build
	$(PYTHON) tools/generate_assets.py --test

$(PRG): $(SOURCES) build/assets.inc
	$(ACME) $(ACMEFLAGS) --outfile $@ --symbollist build/minigolf.sym --report build/minigolf.report src/main.asm
	$(PYTHON) tools/check_build.py minigolf

$(TEST_PRG): $(SOURCES) build/assets-test.inc
	$(ACME) $(ACMEFLAGS) -DTEST_BUILD=1 --outfile $@ --symbollist build/minigolf-test.sym src/main.asm
	$(PYTHON) tools/check_build.py minigolf-test

run: $(PRG)
	$(VICE) -model c16 -pal -ramsize 16 $(if $(strip $(JOYDEV)),-joydev1 $(JOYDEV)) +joystick1autofire -autostartprgmode 1 -autostart-delay 1 -autostart-warp -autostart $(PRG)

# Try one hole: make play HOLE=5 starts the round there (no size check).
HOLE ?= 1
play: build/assets.inc
	$(ACME) $(ACMEFLAGS) -DSTART_HOLE=$(HOLE) --outfile build/minigolf-play.prg src/main.asm
	$(VICE) -model c16 -pal -ramsize 16 $(if $(strip $(JOYDEV)),-joydev1 $(JOYDEV)) +joystick1autofire -autostartprgmode 1 -autostart-delay 1 -autostart-warp -autostart build/minigolf-play.prg

editor:
	xdg-open tools/course-editor.html

test: $(PRG) $(TEST_PRG)
	$(TEST_PYTHON) -m unittest discover -s tests -p 'test_*.py' -v

smoke: $(TEST_PRG)
	$(PYTHON) tests/vice_smoke.py --prepare-only
	$(VICE) -silent -default -console -model c16 -pal -ramsize 16 -sounddev dummy -warp -autostartprgmode 1 -autostart $(TEST_PRG) -initbreak 0x0200 -moncommands build/vice-pal.mon -monlog -monlogname build/vice-pal.log -limitcycles 40000000
	$(PYTHON) tests/vice_smoke.py --verify-only

budget: $(PRG) $(TEST_PRG)
	$(PYTHON) tools/course_codec.py

benchmark: $(TEST_PRG)
	$(TEST_PYTHON) tools/benchmark_math.py

profile: $(TEST_PRG)
	$(TEST_PYTHON) tools/profile_sweep.py

preview: $(TEST_PRG)
	$(TEST_PYTHON) tools/preview_courses.py

screenshot: $(PRG)
	$(TEST_PYTHON) tools/game_screenshot.py

check: test smoke

clean:
	$(PYTHON) -c 'import shutil; shutil.rmtree("build", ignore_errors=True)'
