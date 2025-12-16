@extends('admin.layouts.master')

@section('title', 'Management Șoferi')

@section('content')
@php
    // Fallback: dacă view-ul e accesat prin route placeholder, construim datele aici
    if (!isset($drivers)) {
        $query = \App\Models\User::role('driver')
            ->with(['driverProfile', 'documents', 'vehicles'])
            ->withCount(['documents', 'vehicles']);

        $status = request('status');
        if ($status === 'approved') {
            $query->where('is_approved', true);
        } elseif ($status === 'pending') {
            $query->where('is_approved', false)->whereNull('rejection_reason');
        } elseif ($status === 'rejected') {
            $query->whereNotNull('rejection_reason');
        }

        $search = request('search');
        if ($search) {
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                  ->orWhere('email', 'like', "%{$search}%")
                  ->orWhere('phone', 'like', "%{$search}%");
            });
        }

        $drivers = $query->paginate(15)->withQueryString();
    }
@endphp

<div class="container-fluid py-4">
    <div class="d-flex align-items-center justify-content-between mb-3">
        <div>
            <h1 class="h4 mb-0">Management Șoferi (Transportatori)</h1>
            <p class="text-muted mb-0">Listă, filtrare, aprobare/suspendare, documente și vehicule.</p>
        </div>
        <div class="d-flex gap-2">
            <a href="{{ route('admin.drivers.pending') }}" class="btn btn-outline-primary btn-sm">
                <i class="bi bi-hourglass-split me-1"></i> Șoferi în așteptare
            </a>
        </div>
    </div>

    <div class="card mb-3">
        <div class="card-body">
            <form class="row g-2 align-items-end">
                <div class="col-md-3">
                    <label class="form-label mb-1">Căutare</label>
                    <input type="text" name="search" value="{{ request('search') }}" class="form-control" placeholder="Nume, email, telefon">
                </div>
                <div class="col-md-3">
                    <label class="form-label mb-1">Status</label>
                    <select name="status" class="form-select">
                        <option value="">Toți</option>
                        <option value="approved" @selected(request('status')==='approved')>Aprobați</option>
                        <option value="pending" @selected(request('status')==='pending')>În așteptare</option>
                        <option value="rejected" @selected(request('status')==='rejected')>Respinși</option>
                    </select>
                </div>
                <div class="col-md-2">
                    <label class="form-label mb-1">&nbsp;</label>
                    <button class="btn btn-primary w-100"><i class="bi bi-search me-1"></i> Filtrează</button>
                </div>
                <div class="col-md-2">
                    <label class="form-label mb-1">&nbsp;</label>
                    <a href="{{ route('admin.drivers.index') }}" class="btn btn-outline-secondary w-100">Reset</a>
                </div>
            </form>
        </div>
    </div>

    <div class="card">
        <div class="card-body">
            <div class="table-responsive">
                <table class="table table-striped align-middle">
                    <thead>
                        <tr>
                            <th>#</th>
                            <th>Șofer</th>
                            <th>Contact</th>
                            <th>Status</th>
                            <th>Docs</th>
                            <th>Vehicule</th>
                            <th>Rating</th>
                            <th class="text-end">Acțiuni</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($drivers as $driver)
                            <tr>
                                <td>{{ $driver->id }}</td>
                                <td>
                                    <div class="d-flex align-items-center">
                                        @if($driver->profile_photo)
                                            <img src="{{ asset('storage/' . $driver->profile_photo) }}" class="rounded-circle me-2" style="width:38px;height:38px;" alt="{{ $driver->name }}">
                                        @else
                                            <div class="rounded-circle bg-secondary text-white me-2 d-flex align-items-center justify-content-center" style="width:38px;height:38px;">
                                                {{ strtoupper(substr($driver->name,0,1)) }}
                                            </div>
                                        @endif
                                        <div>
                                            <div class="fw-bold">{{ $driver->name }}</div>
                                            <small class="text-muted">Creat: {{ $driver->created_at?->format('d.m.Y') }}</small>
                                        </div>
                                    </div>
                                </td>
                                <td>
                                    <div>{{ $driver->email }}</div>
                                    <div class="text-muted">{{ $driver->phone ?? '—' }}</div>
                                </td>
                                <td>
                                    @if($driver->is_approved)
                                        <span class="badge bg-success">Aprobat</span>
                                    @elseif($driver->rejection_reason)
        Полыс:  днкие    @else
                                        <span class="badge bg-warning text-dark">În așteptare</span>
                                    @endif
                                    @if(!empty($driver->is_suspended))
                                        <div><span class="badge bg-secondary mt-1">Suspendat</span></div>
                                    @endif
                                </td>
                                <td>
                                    <span class="badge bg-info">{{ $driver->documents_count ?? $driver->documents->count() }}</span>
                                </td>
                                <td>
                                    <span class="badge bg-info">{{ $driver->vehicles_count ?? $driver->vehicles->count() }}</span>
                                </td>
                                <td>
                                    @php $rating = $driver->average_rating ?? 0; @endphp
                                    <div class="text-warning">
                                        @for($i=1;$i<=5;$i++)
                                            @if($i <= round($rating))<i class="fas fa-star"></i>@else<i class="far fa-star"></i>@endif
                                        @endfor
                                        <small class="text-muted ms-1">{{ number_format($rating,1) }}</small>
                                    </div>
                                </td>
                                <td class="text-end">
                                    <div class="btn-group btn-group-sm">
                                        <a href="{{ route('admin.drivers.show_approval', $driver->id) }}" class="btn btn-outline-primary" title="Detalii">
                                            <i class="bi bi-eye"></i>
                                        </a>
                                        @if(!$driver->is_approved && !$driver->rejection_reason)
                                            <form method="POST" action="{{ route('drivers.approve', $driver->id) }}" class="d-inline">@csrf
                                                <button class="btn btn-outline-success" title="Aprobă"><i class="bi bi-check"></i></button>
                                            </form>
                                            <form method="POST" action="{{ route('drivers.reject', $driver->id) }}" class="d-inline">@csrf
                                                <input type="hidden" name="rejection_reason" value="Respins din admin">
                                                <button class="btn btn-outline-danger" title="Respinge"><i class="bi bi-x"></i></button>
                                            </form>
                                        @endif
                                    </div>
                                </td>
                            </tr>
                        @empty
                            <tr><td colspan="8" class="text-center text-muted">Niciun șofer găsit.</td></tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
            <div class="mt-3">
                {{ $drivers->links() }}
            </div>
        </div>
    </div>
</div>
@endsection

