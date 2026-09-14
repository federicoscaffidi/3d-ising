# 3d-ising

Monte Carlo simulation of the 3D Ising model (J = 1, periodic boundaries) with zero-temperature descent, single-spin Metropolis and Wolff cluster updates, in one NumPy notebook.

Course project for *Stochastic Processes and Simulations in Natural Sciences* — Federico Scaffidi Muta, Andrea Porta.

## Headline result

<TODO: Federico — one sentence stating the main finding. The notebook's markdown reads the ferromagnetic–paramagnetic transition off the ⟨|m|⟩(T) curves at T ≈ 4.5 (J/k_B units), but no cell computes an estimate of T_c; to quote a number here you would need to add e.g. a susceptibility-peak or Binder-cumulant estimate and run it.>

All eight figures are embedded in `3d_ising.ipynb`, produced by a single seeded top-to-bottom run (execution counts 1–22) in the environment described below; simulation parameters are tabulated in Appendix B of the notebook.

## Quickstart — clean clone to one reproduced number

Verified with Python 3.13.12 on macOS (arm64).

```bash
git clone https://github.com/federicoscaffidi/3d-ising.git
cd 3d-ising
python3.13 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Then either open `3d_ising.ipynb` in Jupyter/VS Code with the `.venv` interpreter as kernel and run the cells under **Set up** and **Initialise the 3D Ising model**, or run the whole notebook headless:

```bash
python -m nbconvert --to notebook --execute --ExecutePreprocessor.timeout=-1 \
    --output-dir runs --output 3d_ising_run.ipynb 3d_ising.ipynb
```

Expected output of the initial-configuration cell (L = 10, seed 0):

```text
Initial Energy: -24.0
Initial Magnetization: 0.074
```

Full headless run time: 853 s wall (≈14 min) on an Apple-silicon Mac, measured 2026-09-14 with the command above; all Monte Carlo loops are pure Python. The run produced all 8 figures with no errors.

The notebook seeds NumPy's global RNG once (`np.random.seed(0)`), so a top-to-bottom run reproduces the embedded figures exactly.

## Repo map

| Path | What it is |
| --- | --- |
| `3d_ising.ipynb` | the project: model setup, three dynamics, temperature sweeps, discussion, appendices (simulated tempering, parameter table) and bibliography. Executed outputs included; re-run to regenerate them |
| `requirements.txt` | pinned dependencies, read from the verified environment |
| `.gitignore` | keeps the venv, rendered HTML, executed copies (`runs/`) and result data out of git |
| `LICENSE` | GPL-3.0 |

## Method

The lattice is L×L×L with spins ±1 stored as a flat vector of length N = L³; a precomputed (N, 6) neighbour table implements periodic boundaries so every update is index arithmetic. Energy is E = −Σ⟨ij⟩ sᵢsⱼ with each bond counted once; the observable is |m| = |Σᵢ sᵢ| / N. Three dynamics are implemented: (i) a T = 0 single-flip descent that accepts only energy-lowering moves (L = 10, 10⁵ steps); (ii) single-spin Metropolis with local ΔE = 2 sᵢ Σⱼ sⱼ, acceptance min(1, e^{−ΔE/T}), organised in sweeps of N attempted flips (fixed T = 2.9, then a sweep over 33 temperatures in [0.5, 8.0] for L ∈ {6, 8, 10} with 400 burn-in and 1000 measurement sweeps per temperature, sampled every 5, warm-started across temperatures); (iii) Wolff single-cluster updates with P_add = 1 − e^{−2/T} and ΔE from boundary bonds (fixed T = 2.9 from an ordered start, then the same three sizes over 33 temperatures with 2000 burn-in and 5000 recorded cluster flips per temperature). Mean energy and mean |m| per temperature are plotted against T for each L.

## Limitations

Read from the code, not from the write-up:

- One Monte Carlo run per temperature; means are taken over autocorrelated samples and no error bars are computed.
- L ≤ 10 (N ≤ 1000); the Monte Carlo loops are pure Python, which bounds the reachable sizes and sweep counts.
- No cell estimates T_c numerically: the write-up reads T ≈ 4.5 off the ⟨|m|⟩(T) curves by eye. Susceptibility and autocorrelation times are not computed.
- Simulated tempering is discussed as a possible extension only; the implementation is not in this notebook.

## References

Full bibliography with DOIs is at the end of the notebook.

1. Metropolis, Rosenbluth, Rosenbluth, Teller, Teller — J. Chem. Phys. 21, 1087 (1953)
2. Hastings — Biometrika 57, 97 (1970)
3. Wolff — Phys. Rev. Lett. 62, 361 (1989)
4. Marinari, Parisi — Europhys. Lett. 19, 451 (1992)
5. Ferrenberg, Xu, Landau — Phys. Rev. E 97, 043301 (2018): K_c = 0.221654626(5), i.e. T_c ≈ 4.5115
6. Hou, Fang, Wang, Hu, Deng — Phys. Rev. E 99, 042150 (2019): fractal dimension of critical FK clusters
7. Newman, Barkema — *Monte Carlo Methods in Statistical Physics*, OUP (1999)

## Licence

GPL-3.0 — see `LICENSE`.
