// Mémoire vidéo de la carte : Godot ne la donne pas. Sous Windows, par DXGI chargé à l'exécution
// (rien à lier). Ailleurs : inconnue.
#include "relief_hd.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <dxgi.h>

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
#else
double godot::ReliefHD::memoire_video() const {
	return 0.0;
}
#endif
