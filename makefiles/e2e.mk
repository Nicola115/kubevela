
.PHONY: e2e-setup-core
e2e-setup-core:
	sh ./hack/e2e/modify_charts.sh
	helm upgrade --install --create-namespace --namespace vela-system --set image.pullPolicy=IfNotPresent --set image.repository=vela-core-test --set applicationRevisionLimit=5 --set dependCheckWait=10s --set image.tag=$(GIT_COMMIT) --wait kubevela ./charts/vela-core
	kubectl wait --for=condition=Available deployment/kubevela-vela-core -n vela-system --timeout=180s
	go run ./e2e/addon/mock &

.PHONY: setup-runtime-e2e-cluster
setup-runtime-e2e-cluster:
	helm upgrade --install --create-namespace --namespace vela-system --kubeconfig=$(RUNTIME_CLUSTER_CONFIG) --set image.pullPolicy=IfNotPresent --set image.repository=vela-runtime-rollout-test --set image.tag=$(GIT_COMMIT) --wait vela-rollout ./runtime/rollout/charts

.PHONY: e2e-setup
e2e-setup:
	helm install kruise https://github.com/openkruise/kruise/releases/download/v0.9.0/kruise-chart.tgz --set featureGates="PreDownloadImageForInPlaceUpdate=true"
	sh ./hack/e2e/modify_charts.sh
	helm upgrade --install --create-namespace --namespace vela-system --set image.pullPolicy=IfNotPresent --set image.repository=vela-core-test --set applicationRevisionLimit=5 --set dependCheckWait=10s --set image.tag=$(GIT_COMMIT) --wait kubevela ./charts/vela-core
	helm upgrade --install --create-namespace --namespace oam-runtime-system --set image.pullPolicy=IfNotPresent --set image.repository=vela-core-test --set dependCheckWait=10s --set image.tag=$(GIT_COMMIT) --wait oam-runtime ./charts/oam-runtime
	go run ./e2e/addon/mock &
	bin/vela addon enable fluxcd
	bin/vela addon enable terraform
	bin/vela addon enable terraform-alibaba ALICLOUD_ACCESS_KEY=xxx ALICLOUD_SECRET_KEY=yyy ALICLOUD_REGION=cn-beijing
	ginkgo version
	ginkgo -v -r e2e/setup

	timeout 600s bash -c -- 'while true; do kubectl get ns flux-system; if [ $$? -eq 0 ] ; then break; else sleep 5; fi;done'
	kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=vela-core,app.kubernetes.io/instance=kubevela -n vela-system --timeout=600s
	kubectl wait --for=condition=Ready pod -l app=source-controller -n flux-system --timeout=600s
	kubectl wait --for=condition=Ready pod -l app=helm-controller -n flux-system --timeout=600s

.PHONY: e2e-api-test
e2e-api-test:
	# Run e2e test
	ginkgo -v -skipPackage capability,setup,application -r e2e
	ginkgo -v -r e2e/application

ADDONSERVER = $(shell pgrep vela_addon_mock_server)


.PHONY: e2e-apiserver-test
e2e-apiserver-test:
	pkill vela_addon_mock_server || true
	go run ./e2e/addon/mock/vela_addon_mock_server.go &
	go test -v -coverpkg=./... -coverprofile=/tmp/e2e_apiserver_test.out ./test/e2e-apiserver-test
	@$(OK) tests pass

.PHONY: e2e-test
e2e-test:
	# Run e2e test
	ginkgo -v  --skip="rollout related e2e-test." ./test/e2e-test
	@$(OK) tests pass

.PHONY: e2e-addon-test
e2e-addon-test:
	cp bin/vela /tmp/
	ginkgo -v ./test/e2e-addon-test
	@$(OK) tests pass

.PHONY: e2e-rollout-test
e2e-rollout-test:
	ginkgo -v  --focus="rollout related e2e-test." ./test/e2e-test
	@$(OK) tests pass

.PHONY: e2e-multicluster-test
e2e-multicluster-test:
	go test -v -coverpkg=./... -coverprofile=/tmp/e2e_multicluster_test.out ./test/e2e-multicluster-test
	@$(OK) tests pass

.PHONY: e2e-cleanup
e2e-cleanup:
	# Clean up
	rm -rf ~/.vela

.PHONY: end-e2e-core
end-e2e-core:
	sh ./hack/e2e/end_e2e_core.sh

.PHONY: end-e2e
end-e2e:
	sh ./hack/e2e/end_e2e.sh