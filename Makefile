SHELL := /bin/bash -o pipefail
VERSION := $(shell git describe --tags --abbrev=0 || echo "dev")

fetch:
	go mod download
	go mod tidy
clean:
	rm -f ./kubesec
	rm -rf ./build

fmt:
	gofmt -l -s -w `find . -type f -name '*.go' -not -path "./vendor/*" -not -path "./.tmp/*"`

test:
	KUBESEC_TEST_AWS_KMS_KEY= KUBESEC_TEST_GCP_KMS_KEY= make .test

test-integration:
	test -n "$(KUBESEC_TEST_AWS_KMS_KEY)" # $$KUBESEC_TEST_AWS_KMS_KEY must be set
	test -n "$(KUBESEC_TEST_GCP_KMS_KEY)" # $$KUBESEC_TEST_GCP_KMS_KEY must be set
	make .test

.test:
	go vet ./...
	(! gofmt -s -d . | grep '^')
	go test -v ./...

test-coverage:
	go vet ./...
	(! gofmt -s -d . | grep '^')
	go test -v ./... -coverprofile=./coverage.profile -cover
	go tool cover -html=coverage.profile -o coverage.html
	rm -f coverage.profile

import-gpgkeys-for-test:
	gpg2 --import .ci/jean-luc.picard.pubkey
	gpg2 --allow-secret-key-import --import .ci/jean-luc.picard.seckey
	gpg2 --keyserver pgp.mit.edu --recv-keys 160A7A9CF46221A56B06AD64461A804F2609FD89 72ECF46A56B4AD39C907BBB71646B01B86E50310 \
	|| gpg2 --keyserver keyserver.ubuntu.com --recv-keys 160A7A9CF46221A56B06AD64461A804F2609FD89 72ECF46A56B4AD39C907BBB71646B01B86E50310

build:
	go build -ldflags "-X main.version=${VERSION}"

build-release:
	env CGO_ENABLED=0 gox -verbose \
	-ldflags "-X main.version=${VERSION}" \
	-osarch="windows/amd64 linux/amd64 darwin/amd64" \
	-output="release/{{.Dir}}-${VERSION}-{{.OS}}-{{.Arch}}" .

sign-release:
	for file in $$(ls release/kubesec-${VERSION}-*); do gpg --detach-sig --sign -a $$file; done

publish: clean build-release sign-release
	test -n "$(GITHUB_TOKEN)" # $$GITHUB_TOKEN must be set
	github-release release --user shyiko --repo kubesec --tag ${VERSION} \
	--name "${VERSION}" --description "${VERSION}" && \
	github-release upload --user shyiko --repo kubesec --tag ${VERSION} \
	--name "kubesec-${VERSION}-windows-amd64.exe" --file release/kubesec-${VERSION}-windows-amd64.exe; \
	github-release upload --user shyiko --repo kubesec --tag ${VERSION} \
	--name "kubesec-${VERSION}-windows-amd64.exe.asc" --file release/kubesec-${VERSION}-windows-amd64.exe.asc; \
	for qualifier in darwin-amd64 linux-amd64 ; do \
		github-release upload --user shyiko --repo kubesec --tag ${VERSION} \
		--name "kubesec-${VERSION}-$$qualifier" --file release/kubesec-${VERSION}-$$qualifier; \
		github-release upload --user shyiko --repo kubesec --tag ${VERSION} \
		--name "kubesec-${VERSION}-$$qualifier.asc" --file release/kubesec-${VERSION}-$$qualifier.asc; \
	done

deploy-to-homebrew:
	VERSION=${VERSION} sh .deploy-to-homebrew

build-docker-image:
	docker build -f kubesec-playground.dockerfile --build-arg KUBESEC_VERSION=${VERSION} -t shyiko/kubesec-playground:${VERSION} .

push-docker-image: build-docker-image
	docker push shyiko/kubesec-playground:${VERSION}


