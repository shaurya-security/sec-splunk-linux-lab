# Generated SPL

One `.spl` per Sigma rule, deployed by `tools/deploy_sigma_searches.py`.

**Status: hand-authored, NOT yet converter-verified.** `sigma-cli` / `pysigma-backend-splunk`
could not be installed in the authoring environment (PyPI unreachable). These files were written to
match `detections/sigma/pipelines/lab_splunk.yml`. Before release, run on a machine with PyPI access:

    pip install -r requirements-dev.txt
    sigma convert -t splunk -p detections/sigma/pipelines/lab_splunk.yml detections/sigma/

review the output against these files, replace them with reviewed output (or keep the hand-written
correlations and document why), and record the pinned versions in `requirements-dev.txt`.

Windows correlations use `src_ip` (= `IpAddress`, with `-`/loopback treated as null).
