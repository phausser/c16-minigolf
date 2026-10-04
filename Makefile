ACME ?= acme
VICE ?= xplus4
PYTHON ?= python3
TEST_PYTHON ?= .venv/bin/python

PRG := build/minigolf.prg
SOURCES := $(wildcard src/*.asm src/*.inc)

.PHONY: all run test smoke budget benchmark profile check clean
all: $(PRG)

build:
	mkdir -p build

build/assets.inc: tools/generate_assets.py assets/test-course.json | build
	$(PYTHON) tools/generate_assets.py

$(PRG): $(SOURCES) build/assets.inc
	$(ACME) --cpu 6502 --format cbm --strict-segments --outfile $@ --symbollist build/minigolf.sym --report build/minigolf.report src/main.asm
	$(PYTHON) tools/check_build.py

run: $(PRG)
	$(VICE) -default -model c16 -pal -ramsize 16 -autostartprgmode 1 -autostart-delay 1 -autostart-warp -autostart $(PRG)

test: $(PRG)
	$(TEST_PYTHON) -m unittest discover -s tests -p 'test_*.py' -v

smoke: $(PRG)
	$(PYTHON) tests/vice_smoke.py --prepare-only
	$(VICE) -silent -default -console -model c16 -pal -ramsize 16 -sounddev dummy -warp -autostartprgmode 1 -autostart $(PRG) -initbreak 0x0200 -moncommands build/vice-pal.mon -monlog -monlogname build/vice-pal.log -limitcycles 20000000
	$(PYTHON) tests/vice_smoke.py --verify-only

budget: $(PRG)
	$(PYTHON) tools/course_codec.py

benchmark: $(PRG)
	$(TEST_PYTHON) tools/benchmark_math.py

profile: $(PRG)
	$(TEST_PYTHON) tools/profile_sweep.py

check: test smoke

clean:
	$(PYTHON) -c 'import shutil; shutil.rmtree("build", ignore_errors=True)'
