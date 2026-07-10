# Regression Notes

<!-- nix-file-loc:start -->
232 lib/stages/compiled-services.nix | state=split-required | reason=FS-630-SMS-020 printer payload auth module wired; extract printer+media payload auth modules to shared boundary
<!-- nix-file-loc:end -->

- FS-030-HDS-010-SDS-020-SMS-010 selector-fanout policy-bypass classification corrected | state=solved | evidence=tests/test-FS-030-HDS-010-SDS-020-SMS-010.sh | notes=shared upstream-selector multi-core fanout and shared downstream-selector multi-access fanout are valid topology and do not create traffic-path authority without modeled relations
- FS-620-HDS-010-SDS-010-SMS-010 compiler isolation classification construction proof restored | state=solved | evidence=tests/test-FS-620-HDS-010-SDS-010-SMS-010.sh
