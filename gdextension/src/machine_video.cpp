// Mémoire vidéo de la carte : Godot ne la donne pas. Sous Windows, par DXGI chargé à l'exécution
// (rien à lier). Ailleurs : inconnue.
#include "relief_hd.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <dxgi1_4.h>

double godot::ReliefHD::memoire_video() const {
	HMODULE dll = LoadLibraryW(L"dxgi.dll");
	if (dll == nullptr) {
		return 0.0;
	}
	typedef HRESULT(WINAPI * Creer)(REFIID, void **);
	Creer creer = reinterpret_cast<Creer>(reinterpret_cast<void *>(GetProcAddress(dll, "CreateDXGIFactory1")));
	double meilleur = 0.0;
	IDXGIFactory1 *fabrique = nullptr;
	if (creer != nullptr && SUCCEEDED(creer(__uuidof(IDXGIFactory1), reinterpret_cast<void **>(&fabrique)))) {
		IDXGIAdapter1 *carte = nullptr;
		for (UINT i = 0; fabrique->EnumAdapters1(i, &carte) != DXGI_ERROR_NOT_FOUND; i++) {
			DXGI_ADAPTER_DESC1 d;
			if (SUCCEEDED(carte->GetDesc1(&d))) {
				const double go = double(d.DedicatedVideoMemory) / 1073741824.0;
				if (go > meilleur) {
					meilleur = go;
				}
			}
			carte->Release();
		}
		fabrique->Release();
	}
	FreeLibrary(dll);
	return meilleur;
}
// Budget de mémoire vidéo que le système accorde au jeu, et ce qu'il en utilise (Go), sur la carte
// qui dessine (la plus grosse mémoire dédiée, comme ci-dessus) : [budget, usage], [0, 0] si inconnu.
// Sur une puce intégrée, la mémoire « dédiée » n'est que la réserve du BIOS ; le budget, lui, compte
// la mémoire partagée — c'est lui qui dit quand on va déborder (images de 1 à 20 s, 24/10/2026).
godot::PackedFloat32Array godot::ReliefHD::budget_video() const {
	PackedFloat32Array r;
	r.push_back(0.0f);
	r.push_back(0.0f);
	HMODULE dll = LoadLibraryW(L"dxgi.dll");
	if (dll == nullptr) {
		return r;
	}
	typedef HRESULT(WINAPI * Creer)(REFIID, void **);
	Creer creer = reinterpret_cast<Creer>(reinterpret_cast<void *>(GetProcAddress(dll, "CreateDXGIFactory1")));
	IDXGIFactory1 *fabrique = nullptr;
	if (creer != nullptr && SUCCEEDED(creer(__uuidof(IDXGIFactory1), reinterpret_cast<void **>(&fabrique)))) {
		IDXGIAdapter1 *carte = nullptr;
		SIZE_T meilleur = 0;
		bool trouve = false;
		for (UINT i = 0; fabrique->EnumAdapters1(i, &carte) != DXGI_ERROR_NOT_FOUND; i++) {
			DXGI_ADAPTER_DESC1 d;
			if (SUCCEEDED(carte->GetDesc1(&d)) && !(d.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)
					&& (!trouve || d.DedicatedVideoMemory > meilleur)) {
				IDXGIAdapter3 *c3 = nullptr;
				if (SUCCEEDED(carte->QueryInterface(__uuidof(IDXGIAdapter3), reinterpret_cast<void **>(&c3)))) {
					DXGI_QUERY_VIDEO_MEMORY_INFO local = {};
					DXGI_QUERY_VIDEO_MEMORY_INFO partagee = {};
					c3->QueryVideoMemoryInfo(0, DXGI_MEMORY_SEGMENT_GROUP_LOCAL, &local);
					c3->QueryVideoMemoryInfo(0, DXGI_MEMORY_SEGMENT_GROUP_NON_LOCAL, &partagee);
					// carte dédiée : sa mémoire ; puce intégrée (presque rien en local) : les deux
					const bool integree = d.DedicatedVideoMemory < (SIZE_T(2) << 30);
					double budget = double(local.Budget);
					double usage = double(local.CurrentUsage);
					if (integree) {
						budget += double(partagee.Budget);
						usage += double(partagee.CurrentUsage);
					}
					r.set(0, float(budget / 1073741824.0));
					r.set(1, float(usage / 1073741824.0));
					meilleur = d.DedicatedVideoMemory;
					trouve = true;
					c3->Release();
				}
			}
			carte->Release();
		}
		fabrique->Release();
	}
	FreeLibrary(dll);
	return r;
}
#else
double godot::ReliefHD::memoire_video() const {
	return 0.0;
}

godot::PackedFloat32Array godot::ReliefHD::budget_video() const {
	PackedFloat32Array r;
	r.push_back(0.0f);
	r.push_back(0.0f);
	return r;
}
#endif
