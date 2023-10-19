MAKEFLAGS = -s ${MAX_PARALLEL_MAKEFLAG}
SHELL = /bin/bash
ROOTDIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

ISOLATED_VM_VERSION_COMMAND="require('./node_modules/isolated-vm/package.json').version"
ISOLATED_VM_VERSION=$(shell node -p -e $(ISOLATED_VM_VERSION_COMMAND))

PIPENV := PYTHONPATH=${ROOTDIR} PIPENV_IGNORE_VIRTUALENVS=1 pipenv
MIN_PIPENV_VERSION = "2022.10.4"

DOC_DISABLE_SOURCES ?= true
DOC_GIT_REVISION ?= main


# Aliases
bs: bootstrap

###############################################################################
# Bootstrapping - get the local machine ready

.PHONY: _bootstrap-install-pnpm
_bootstrap-install-pnpm:
	./scripts/dev/install-pnpm.sh

.PHONY: _bootstrap-node
_bootstrap-node:
	.pnpm_install/bin/pnpm install --frozen-lockfile

.PHONY: _bootstrap-python
_bootstrap-python:
	${PIPENV} sync

.PHONY: _bootstrap-python-requirements
_bootstrap-python-requirements:
	# Ensure requirements.txt (used by Read the Docs) is in sync.
	# Keep this separate from _bootstrap-python since the output changes based
	# on the version of pipenv installed.
	PIPENV_VERSION="$(shell ${PIPENV} --version | cut -d ' ' -f 3 | tr '.' ' ' | xargs printf '%02d')"; \
	MIN_PIPENV_VERSION="$(shell echo ${MIN_PIPENV_VERSION} | tr '.' ' ' | xargs printf '%02d')"; \
	if [[ $$PIPENV_VERSION -lt $$MIN_PIPENV_VERSION ]]; then \
		echo "pipenv version ${MIN_PIPENV_VERSION} or later is required. To update it, run: pip3 install --upgrade pipenv"; \
		exit 1; \
	fi
	echo "# Autogenerated by 'make bs'" > requirements.txt
	echo "# If the format has changed, update MIN_PIPENV_VERSION in Makefile" >> requirements.txt
	${PIPENV} requirements >> requirements.txt

.PHONY: _bootstrap-system-packages
_bootstrap-system-packages:
	# Install the packages required by the MkDocs Material social plugin if
	# homebrew is available. These appear to come pre-installed in most linux
	# environments.
	# https://squidfunk.github.io/mkdocs-material/setup/setting-up-social-cards/#dependencies
	if command -v brew &> /dev/null; then \
		brew install cairo freetype libffi libjpeg libpng zlib; \
	fi

.PHONY: _bootstrap-githooks
_bootstrap-githooks: clean-githooks
	-(cd ${ROOTDIR}; scripts/dev/git-hooks.sh --install)

.PHONY: _bootstrap-doc-tools
_bootstrap-doc-tools:
	# Image libraries required by the social cards plugin for MkDocs Material.
	sudo apt-get install libcairo2-dev libfreetype6-dev libffi-dev libjpeg-dev libpng-dev libz-dev

.PHONY: _bootstrap-renovate
_bootstrap-renovate:
	# _bootstrap-doc-tools doesn't work in renovate
	sudo apt-get install libjpeg-dev

.PHONY: bootstrap
bootstrap:
	$(MAKE) MAKEFLAGS= _bootstrap-install-pnpm
	$(MAKE) MAKEFLAGS= _bootstrap-node
	$(MAKE) MAKEFLAGS= _bootstrap-system-packages
	$(MAKE) MAKEFLAGS= _bootstrap-python
	$(MAKE) MAKEFLAGS= _bootstrap-python-requirements
	$(MAKE) MAKEFLAGS= _bootstrap-githooks
	echo
	echo '  make bootstrap complete!'
	echo

###############################################################################
# Lint / tests

.PHONY: lint
lint:
	find . -name "*.ts" | grep -v /dist/ | grep -v /node_modules/ | grep -v "\.d\.ts" | xargs ${ROOTDIR}/node_modules/.bin/eslint

	# Ensure markdown has frontmatter
	MISSING="$(shell awk '/^[^-]/{print FILENAME}; {nextfile}' ./docs/**/*.md)"; \
	if [[ "$$MISSING" != "" ]]; then \
		echo "These markdown files are missing frontmatter: $$MISSING"; \
		exit 1; \
	fi

	# Markdown lint.
	npx remark docs --quiet --frail --ignore-pattern 'docs/reference/*'

	# Spellcheck docs lint.
	npx cspell lint '{docs,documentation}/**/*.md' 'CHANGELOG.md' --no-progress

	# Changelog lint.
	npx kacl lint

	# release-it only understands "Unreleased" as the name of an upcoming release
	RELEASE_NAME="$(shell egrep -m 1 '^## ' CHANGELOG.md | egrep -v "^## \[")"; \
	if [[ "$$RELEASE_NAME" != "" && "$$RELEASE_NAME" != "## Unreleased" ]]; then \
		echo "Changelog should begin with "## Unreleased", not $$RELEASE_NAME"; \
		exit 1; \
	fi

.PHONY: lint-fix
lint-fix:
	find . -name "*.ts" | grep -v /dist/ | grep -v /node_modules/ | grep -v .d.ts | xargs ${ROOTDIR}/node_modules/.bin/eslint --fix

.PHONY: do-compile-isolated-vm-18
do-compile-isolated-vm-18:
	rm -rf build-isolated-vm-18
	mkdir build-isolated-vm-18 && \
		cd build-isolated-vm-18 && \
		npm init -y && \
		docker run --rm --platform linux/amd64 -v `pwd`:/var/task public.ecr.aws/sam/build-nodejs18.x:latest \
		  bash -c "yum -y install openssl-devel && npm install isolated-vm@${ISOLATED_VM_VERSION}"
	mkdir -p runtime/native/node18/x86_64/isolated-vm/out
	cp build-isolated-vm-18/node_modules/isolated-vm/package.json runtime/native/node18/x86_64/isolated-vm/
	cp build-isolated-vm-18/node_modules/isolated-vm/isolated-vm.js runtime/native/node18/x86_64/isolated-vm/
	cp build-isolated-vm-18/node_modules/isolated-vm/out/isolated_vm.node runtime/native/node18/x86_64/isolated-vm/out/
	rm -rf build-isolated-vm-18

.PHONY: compile-isolated-vm-18
compile-isolated-vm-18:
	if [ ! -f './runtime/native/node18/x86_64/isolated-vm/package.json' ] || \
	   [ `node -p -e "require('./runtime/native/node18/x86_64/isolated-vm/package.json').version"` != $(ISOLATED_VM_VERSION) ]; \
		then $(MAKE) do-compile-isolated-vm-18; \
		else echo "isolated-vm version matches, skipping."; \
	fi

.PHONY: compile-thunk
compile-thunk:
	echo "Compiling thunk... if this fails with <Cannot find module 'isolated-vm'> errors, then run: pnpm add isolated-vm";
	# This bundle is loaded into ivm, better to use iife to avoid local symbols leak to global.
	# We need the NODE_DEBUG=false because "util.format" depends on debuglog which depends
	# on the value of NODE_DEBUG (https://github.com/nodejs/node/blob/6b055f385744d2ca71c19d46a0ec3bcfc51f5cd3/lib/internal/util/debuglog.js#L21)
	${ROOTDIR}/node_modules/.bin/esbuild ${ROOTDIR}/runtime/thunk/thunk.ts \
		--bundle \
		--outfile=${ROOTDIR}/bundles/thunk_bundle.js \
		--inject:${ROOTDIR}/testing/injections/buffer_shim.js \
		--format=iife \
		--define:process.env.IN_ISOLATED_VM_OR_BROWSER=true \
		--define:process.env.NODE_DEBUG=false \
		--global-name=module.exports \
		--keep-names \
		--target=es2020;

.PHONY: compile-ts
compile-ts:
	echo "Compiling Typescript... if this fails to build isolated-vm, you may need to install plain python (python 2 was removed in MacOS Monterey 12.3)";
	rm -rf dist/
	${ROOTDIR}/node_modules/.bin/tsc

	$(MAKE) compile-thunk
	$(MAKE) compile-documentation-scripts

	# copy it to dist/ to make it available after packaging.
	mkdir -p ${ROOTDIR}/dist/bundles/ && cp ${ROOTDIR}/bundles/thunk_bundle.js ${ROOTDIR}/dist/bundles/thunk_bundle.js

	# copy buffer.d.ts to be used by monaco browser.
	cp ${ROOTDIR}/node_modules/buffer/index.d.ts ${ROOTDIR}/dist/buffer.d.ts

	# This bundle is used by the Pack studio to compile the pack bundle in the browser. It will be loaded in both
	# browser and isolated-vm. In the browser, the pack bundle is loaded in an iframe to extract pack metadata.
	# In lambda, the pack bundle actually runs formulas.
	#
	# isolated-vm environment is approximately es2020. It's known that es2021 will break because of Logical assignment
	#
	# We need the NODE_DEBUG=false because "util.format" depends on debuglog which depends
	# on the value of NODE_DEBUG (https://github.com/nodejs/node/blob/6b055f385744d2ca71c19d46a0ec3bcfc51f5cd3/lib/internal/util/debuglog.js#L21)
	${ROOTDIR}/node_modules/.bin/esbuild ${ROOTDIR}/index.ts \
		--bundle \
		--outfile=${ROOTDIR}/dist/bundle.js \
		--format=cjs \
		--define:process.env.IN_ISOLATED_VM_OR_BROWSER=true \
		--define:process.env.NODE_DEBUG=false \
		--minify \
		--keep-names \
		--target=es2020;

.PHONY: compile
compile:
	# Generate isolated-vm binaries that are compatible with Amazon Linux 2.
	$(MAKE) compile-isolated-vm-18

	$(MAKE) compile-ts

	# Generate a typescript file for use in /experimental so the web editor
	# can resolve packs-sdk imports
	${ROOTDIR}/node_modules/.bin/dts-bundle-generator ${ROOTDIR}/index.ts \
  	-o ${ROOTDIR}/dist/bundle.d.ts \
		--no-banner
	# copy these esm format js files to dist directly.
	cp -r ${ROOTDIR}/testing/injections ${ROOTDIR}/dist/testing/

.PHONY: compile-documentation-scripts
compile-documentation-scripts:
	${ROOTDIR}/node_modules/.bin/tsc --project tsconfig.scripts.json

.PHONY: compile-samples
compile-samples:
	${ROOTDIR}/node_modules/.bin/tsc --project ./documentation/samples/tsconfig.json

.PHONY: validate-samples
validate-samples:
	RET=0; \
	for pack in `find documentation/samples/packs -name "*.ts"`; do \
		echo Validating $${pack}...; \
		node dist/cli/coda.js validate --no-checkDeprecationWarnings $${pack}; \
		if [ $? ]; then \
			RET=1; \
		fi; \
	done; \
	exit $$RET

.PHONY: generated-documentation
generated-documentation: compile-samples
	node -r ts-node/register documentation/scripts/documentation_compiler.ts

.PHONY: typedoc
typedoc:
	# Most options loaded from typedoc.js.
	# If you changes this, also update the similar command in typedoc_coverage_test.ts.
	${ROOTDIR}/node_modules/.bin/typedoc index.ts development.ts --options typedoc.js --disableSources "${DOC_DISABLE_SOURCES}" --gitRevision "${DOC_GIT_REVISION}" --out ${ROOTDIR}/docs/reference/sdk
	node -r ts-node/register documentation/scripts/typedoc_post_process.ts

.PHONY: docs
docs: typedoc generated-documentation build-mkdocs

.PHONY: view-docs
view-docs:
	if command -v expect &> /dev/null; then \
		PYTHONPATH=${ROOTDIR} PIPENV_IGNORE_VIRTUALENVS=1 MK_DOCS_SITE_URL=http://localhost:8000/packs-sdk MK_DOCS_GENERATE_CARDS=false expect -c 'set timeout 60; spawn pipenv run mkdocs serve; expect "Serving on"; exec open "http://localhost:8000"; interact'; \
	else \
		PYTHONPATH=${ROOTDIR} PIPENV_IGNORE_VIRTUALENVS=1 MK_DOCS_SITE_URL=http://localhost:8000/packs-sdk MK_DOCS_GENERATE_CARDS=false pipenv run mkdocs serve; \
	fi

.PHONY: optimize-images
optimize-images:
	# Compress pngs.
	npx sharp-cli -i docs/images/*.png -o docs/images/ --optimize

.PHONY: optimize-video
optimize-video:
	# Optimize a video being used as an embedded animation.
	ffmpeg \
		-i "${FILE}" \
		-vcodec libx264 \
		`# Ensure the output format is MP4` \
		-f mp4 \
		`# Set the pixel format to ensure compatibility with certain browsers` \
		-pix_fmt yuv420p \
		`# Crop the video so that it has even dimensions, and scale it to 800px max` \
		-vf "crop=trunc(iw/2)*2:trunc(ih/2)*2,scale='min(800,iw)':-1" \
		`# Set the quality of the video, higher numbers are lower quality` \
		-crf 25 \
		`# Lower the frame rate, to mirror an animated gif` \
		-r 15 \
		`# Drops any audio track` \
		-an \
		`# Only log errors` \
		-loglevel error \
		`# Say yes to overwriting an existing file` \
		-y  \
		${FILE}.tmp; \
	mv ${FILE}.tmp ${FILE}

###############################################################################
### Deployment of documentation ###

# This step generates all the documentation for the SDK using mkdocs and dumps the contents in /site
.PHONY: build-mkdocs
build-mkdocs:
	${PIPENV} run mkdocs build --strict

# This step uploads the documentation for the current package version.
# TODO(spencer): probably need some user handling to make sure there is an update in package.json if the documentation has been updated.
# TODO(spencer): add post-push verify step to probe that it is acutally serving for the different environments?
# These steps assume that the docs have been built

# pass in `FLAGS` to control optional arguments into the documentation push script
# For example, if you wanted to force upload (to skip the existing directory check), you can run
# make publish-docs-<env> FLAGS=--forceUpload
.PHONY: publish-docs-adhoc
publish-docs-adhoc:
	(cd ${ROOTDIR}; ./node_modules/.bin/ts-node documentation/scripts/documentation_publisher.ts push adhoc ${FLAGS})

.PHONY: publish-docs-head
publish-docs-head:
	(cd ${ROOTDIR}; ./node_modules/.bin/ts-node documentation/scripts/documentation_publisher.ts push head ${FLAGS})

.PHONY: publish-docs-staging
publish-docs-staging:
	(cd ${ROOTDIR}; ./node_modules/.bin/ts-node documentation/scripts/documentation_publisher.ts push staging ${FLAGS})

.PHONY: publish-docs-prod
publish-docs-prod:
	(cd ${ROOTDIR}; ./node_modules/.bin/ts-node documentation/scripts/documentation_publisher.ts push prod ${FLAGS})

.PHONY: publish-docs-gh-pages
publish-docs-gh-pages:
	if [ -z ${shell git status -uno | grep "Your branch is up to date with 'origin/main'"} ]; then \
		echo "The documentation can only be published from main at head."; \
		exit 1; \
	fi
	# Build the docs and push them to the gh-pages branch.
	# See: https://www.mkdocs.org/user-guide/deploying-your-docs/#github-pages
	# Including the tag "[ci skip]" in the commit message to prevent CircleCI from building the branch.
	MK_DOCS_SITE_URL=https://coda.github.io/packs-sdk/ ${PIPENV} run mkdocs gh-deploy --message "Deployed {sha} with MkDocs version: {version} [ci skip]"

###############################################################################

.PHONY: test
test:
	TS_NODE_TRANSPILE_ONLY=1 ${ROOTDIR}/node_modules/.bin/mocha test/*_test.ts

.PHONY: test-file
test-file:
	TS_NODE_TRANSPILE_ONLY=1 ${ROOTDIR}/node_modules/.bin/mocha ${FILE}

.PHONY: clean-githooks
clean-githooks:
	-rm -rf ${ROOTDIR}/.git/hooks/* ${ROOTDIR}/.git/hooks.old

.PHONY: clean
clean:
	rm -rf ${ROOTDIR}/dist

.PHONY: build
build: clean lint compile docs

# allow debugging packs sdk with local packs repo.
.PHONY: publish-local
publish-local: build
	cp -r dist/* ../packs/node_modules/@codahq/packs-sdk/dist/

.PHONY: validate-no-changes
validate-no-changes: clean compile docs
	$(eval UNTRACKED_FILES := $(shell git status --short))
	$(eval CHANGED_FILES := $(shell git diff --name-only))
	if [[ -n "${UNTRACKED_FILES}" || -n "${CHANGED_FILES}" ]]; then \
		mkdir -p /tmp/diffs; \
	  git status > /tmp/diffs/status.txt; \
		git diff > /tmp/diffs/diff.txt; \
		echo "The directory is not clean. Run 'make build' and commit all files."; \
		echo "Untracked files: ${UNTRACKED_FILES}"; \
		echo "Changed files: ${CHANGED_FILES}"; \
		echo "More detailed information is available as build artifacts in Circle CI."; \
		exit 1; \
	fi

.PHONY: release
release:
	# this set is taken from esbuild's process https://github.com/evanw/esbuild/blob/master/Makefile#L330
	@npm --version > /dev/null || (echo "The 'npm' command must be in your path to publish" && false)
	@echo "Checking for uncommitted/untracked changes..." && test -z "`git status --porcelain | grep -vE ''`" || \
		(echo "Refusing to publish with these uncommitted/untracked changes:" && \
		git status --porcelain | grep -vE '' && false)
	@echo "Checking for main branch..." && test main = "`git rev-parse --abbrev-ref HEAD`" || \
		(echo "Refusing to publish from non-main branch `git rev-parse --abbrev-ref HEAD`" && false)
	@echo "Checking for unpushed commits..." && git fetch
	@test "" = "`git cherry`" || (echo "Refusing to publish with unpushed commits" && false)

	npm config set //registry.npmjs.org/:_authToken $NPM_TOKEN
	npx release-it --npm.tag=latest --ci ${FLAGS}

.PHONY: release-manual
release-manual:
	# this set is taken from esbuild's process https://github.com/evanw/esbuild/blob/master/Makefile#L330
	@npm --version > /dev/null || (echo "The 'npm' command must be in your path to-*///// publish" && false)
	@echo "Checking for uncommitted/untracked changes..." && test -z "`git status --porcelain | grep -vE ''`" || \
		(echo "Refusing to publish with these uncommitted/untracked changes:" && \
		git status --porcelain | grep -vE '' && false)
	@echo "Checking for unpushed commits..." && git fetch
	@test "" = "`git cherry`" || (echo "Refusing to publish with unpushed commits" && false)

	npx release-it --npm.tag=latest
