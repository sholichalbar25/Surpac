# stockpile_by_string.tcl - Makro Surpac: volume dan tonase beberapa stockpile dalam SATU file .str,
# satu stockpile per string, masing-masing dengan dasar AUTO TOE dan berat jenisnya sendiri.
#
# Makro ini MANDIRI: satu file saja, tanpa Python dan tanpa file pendamping. Seluruh hitungan ada di sini (Tcl),
# dan file .str dibaca lewat perintah bawaan Surpac sehingga .str teks maupun biner bisa dipakai.
#
# Cara pakai: jalankan dengan MACRO PLAYBACK (F6) dan pilih file .tcl ini (dengan ekstensi .tcl).
#
#   Langkah 1  pilih file .str. Makro membacanya dan mencari string yang ada di dalamnya.
#   Langkah 2  sebuah tabel menampilkan setiap string yang ditemukan. Isi berat jenis (t/m3) dan, bila mau,
#              nama untuk tiap stockpile. Berat jenis yang kosong tetap menghasilkan volume, tetapi tanpa ton.
#              Opsi: string yang diabaikan, jenis dasar, toleransi toe, simpan toe, dan laporan CSV.
#   Hasil      tabel hasil (volume dan ton tiap stockpile serta totalnya); laporan lengkapnya juga
#              dicetak di jendela pesan.
#
# Tiap string dianalisis sendiri: titik terendahnya adalah toe-nya, garis luar toe membentuk dasar,
# dan volume dihitung di atas dasar itu.
#
# Satu-satunya pengaturan: jumlah baris maksimum pada tabel langkah 2.
set svMaxPiles 20

# ---------------------------------------------------------------------------------------------
# fungsi bantu umum
# ---------------------------------------------------------------------------------------------

# Escape teks untuk label HTML.
proc svEsc {text} {
    return [string map {& &amp; < &lt; > &gt;} $text]
}

# 1234567.891 -> 1.234.567,89 (format Indonesia; digits = jumlah desimal). Yang bukan angka dikembalikan apa adanya.
proc svFmt {x digits} {
    if {[string length [string trim $x]] == 0} {
        return ""
    }
    if {[catch {format "%.${digits}f" $x} s]} {
        return $x
    }
    if {![regexp {^(-?)([0-9]+)(\.[0-9]+)?$} $s -> sign int frac]} {
        return $s
    }
    while {[regexp {^([0-9]+)([0-9]{3})(,.*)?$} $int -> a b c]} {
        set int "$a,$b$c"
    }
    # tukar pemisah dalam satu langkah: koma -> titik, titik -> koma
    return [string map {, . . ,} "$sign$int$frac"]
}

# "007" -> 7, "0" -> 0 (tanpa expr pada isian pengguna: Tcl 8.5 membaca angka berawalan nol sebagai oktal)
proc svNum {text} {
    set n [string trimleft $text 0]
    if {[string length $n] == 0} {
        set n 0
    }
    return $n
}

# ---------------------------------------------------------------------------------------------
# mesin hitung (Tcl murni)
# ---------------------------------------------------------------------------------------------

# Luas poligon (rumus tali sepatu). Positif bila titiknya berlawanan arah jarum jam.
proc svPolyArea {poly} {
    set s 0.0
    lassign [lindex $poly end] px py
    foreach p $poly {
        lassign $p x y
        set s [expr {$s + $px * $y - $x * $py}]
        set px $x
        set py $y
    }
    return [expr {$s / 2.0}]
}

# Garis luar cembung (monotone chain). Masukan {{x y z} ...}; keluaran berlawanan arah jarum jam, tanpa titik segaris.
proc svHull {pts} {
    if {[llength $pts] < 3} {
        return $pts
    }
    set sorted [lsort -real -index 0 [lsort -real -index 1 $pts]]
    set lo {}
    foreach q $sorted {
        lassign $q qx qy
        while {[llength $lo] >= 2} {
            lassign [lindex $lo end-1] ax ay
            lassign [lindex $lo end] bx by
            if {($bx - $ax) * ($qy - $ay) - ($by - $ay) * ($qx - $ax) <= 0} {
                set lo [lrange $lo 0 end-1]
            } else {
                break
            }
        }
        lappend lo $q
    }
    set up {}
    foreach q [lreverse $sorted] {
        lassign $q qx qy
        while {[llength $up] >= 2} {
            lassign [lindex $up end-1] ax ay
            lassign [lindex $up end] bx by
            if {($bx - $ax) * ($qy - $ay) - ($by - $ay) * ($qx - $ax) <= 0} {
                set up [lrange $up 0 end-1]
            } else {
                break
            }
        }
        lappend up $q
    }
    return [concat [lrange $lo 0 end-1] [lrange $up 0 end-1]]
}

# Tepi poligon sebagai {ax ay dx dy}, untuk uji "di dalam" yang cepat.
proc svEdgeList {poly} {
    set edges {}
    set n [llength $poly]
    for {set i 0} {$i < $n} {incr i} {
        lassign [lindex $poly $i] ax ay
        lassign [lindex $poly [expr {($i + 1) % $n}]] bx by
        lappend edges [list $ax $ay [expr {$bx - $ax}] [expr {$by - $ay}]]
    }
    return $edges
}

# 1 bila titik (px,py) berada di dalam atau di tepi poligon cembung (tepi dari svEdgeList).
proc svInsideEdges {edges px py} {
    foreach e $edges {
        lassign $e ax ay dx dy
        if {$dx * ($py - $ay) - $dy * ($px - $ax) < -1e-9} {
            return 0
        }
    }
    return 1
}

# Urutan penyisipan titik: jalur-jalur horizontal yang dibaca bolak-balik, supaya titik berurutan saling berdekatan
# (pencarian segitiga jadi pendek).
proc svInsertOrder {xs ys} {
    set n [llength $xs]
    set minx [tcl::mathfunc::min {*}$xs]
    set maxx [tcl::mathfunc::max {*}$xs]
    set miny [tcl::mathfunc::min {*}$ys]
    set maxy [tcl::mathfunc::max {*}$ys]
    set w [expr {$maxx - $minx}]
    set h [expr {$maxy - $miny}]
    set strips [expr {max(1, int(sqrt($n / 2.0)))}]
    if {$h <= 0} {
        set h 1.0
    }
    set sw [expr {$h / $strips}]
    set keys {}
    for {set i 0} {$i < $n} {incr i} {
        set s [expr {int(([lindex $ys $i] - $miny) / $sw)}]
        if {$s >= $strips} {
            set s [expr {$strips - 1}]
        }
        set xr [expr {[lindex $xs $i] - $minx}]
        if {$s % 2} {
            set xr [expr {$w - $xr}]
        }
        lappend keys [list [expr {$s * ($w * 2.0 + 2.0) + $xr}] $i]
    }
    set order {}
    foreach k [lsort -real -index 0 $keys] {
        lappend order [lindex $k 1]
    }
    return $order
}

# Jalan dari segitiga nyata t menuju titik (px,py). Mengembalikan segitiga nyata yang memuat titik itu, atau segitiga
# hantu (memuat simpul G) di seberang sisi garis luar bila titik berada di luar garis luar.
# T($t) = {a b c n0 n1 n2}: simpul a b c berlawanan arah jarum jam; n0 = tetangga di seberang sisi b-c,
# n1 = di seberang sisi c-a, n2 = di seberang sisi a-b.
proc svWalk {tv xs ys G t px py} {
    upvar 1 $tv T
    set limit [expr {4 * $T(next) + 20}]
    set steps 0
    while {1} {
        lassign $T($t) a b c n0 n1 n2
        set ax [lindex $xs $a]
        set ay [lindex $ys $a]
        set bx [lindex $xs $b]
        set by [lindex $ys $b]
        set cx [lindex $xs $c]
        set cy [lindex $ys $c]
        set nb -1
        if {($bx - $ax) * ($py - $ay) - ($by - $ay) * ($px - $ax) < 0} {
            set nb $n2
        } elseif {($cx - $bx) * ($py - $by) - ($cy - $by) * ($px - $bx) < 0} {
            set nb $n0
        } elseif {($ax - $cx) * ($py - $cy) - ($ay - $cy) * ($px - $cx) < 0} {
            set nb $n1
        }
        if {$nb < 0} {
            return $t
        }
        lassign $T($nb) q1 q2 q3
        if {$q1 == $G || $q2 == $G || $q3 == $G} {
            return $nb
        }
        set t $nb
        if {[incr steps] > $limit} {
            break
        }
    }
    # jalan berputar (data aneh): pilih segitiga nyata yang paling dekat memuat titik
    set best 0
    set bestVal -1e300
    for {set t 0} {$t < $T(next)} {incr t} {
        lassign $T($t) a b c
        if {$a == $G || $b == $G || $c == $G} {
            continue
        }
        set ax [lindex $xs $a]
        set ay [lindex $ys $a]
        set bx [lindex $xs $b]
        set by [lindex $ys $b]
        set cx [lindex $xs $c]
        set cy [lindex $ys $c]
        set v [expr {min(($bx - $ax) * ($py - $ay) - ($by - $ay) * ($px - $ax),
                         ($cx - $bx) * ($py - $by) - ($cy - $by) * ($px - $bx),
                         ($ax - $cx) * ($py - $cy) - ($ay - $cy) * ($px - $cx))}]
        if {$v > $bestVal} {
            set bestVal $v
            set best $t
        }
    }
    return $best
}

# Triangulasi Delaunay (Bowyer-Watson dengan "segitiga hantu") atas titik 0..n-1. xs ys = koordinat lokal,
# order = urutan penyisipan. Hasil di array T (nama array dari pemanggil) lewat upvar: T(0 .. next-1) = {a b c n0 n1 n2}.
# Simpul n (= G) adalah titik di tak hingga: segitiga yang memuatnya ("hantu") menempel di sisi garis luar, sehingga
# segitiga nyata selalu menutup seluruh garis luar cembung dengan tepat. Pemanggil membuang segitiga yang memuat G.
proc svDelaunay {tv xs ys order} {
    upvar 1 $tv T
    set n [llength $xs]
    set G $n
    array unset T

    # segitiga awal: dua titik pertama dan titik pertama berikutnya yang tidak segaris dengan keduanya
    set i0 [lindex $order 0]
    set i1 [lindex $order 1]
    set x0 [lindex $xs $i0]
    set y0 [lindex $ys $i0]
    set dx [expr {[lindex $xs $i1] - $x0}]
    set dy [expr {[lindex $ys $i1] - $y0}]
    set i2 -1
    set rest {}
    foreach i [lrange $order 2 end] {
        if {$i2 < 0} {
            set cr [expr {$dx * ([lindex $ys $i] - $y0) - $dy * ([lindex $xs $i] - $x0)}]
            if {abs($cr) > 1e-9} {
                set i2 $i
                if {$cr < 0} {
                    # urutkan berlawanan arah jarum jam
                    set i2 $i1
                    set i1 $i
                }
                continue
            }
        }
        lappend rest $i
    }
    if {$i2 < 0} {
        error "titik-titik segaris"
    }
    set T(0) [list $i0 $i1 $i2 2 3 1]
    set T(1) [list $i1 $i0 $G 3 2 0]
    set T(2) [list $i2 $i1 $G 1 3 0]
    set T(3) [list $i0 $i2 $G 2 1 0]
    set T(next) 4
    set last 0
    set stamp 0

    foreach i $rest {
        set px [lindex $xs $i]
        set py [lindex $ys $i]
        set t [svWalk T $xs $ys $G $last $px $py]

        # rongga: segitiga yang bertentangan dengan titik ini (lingkaran luar memuat titik; untuk segitiga hantu:
        # titik berada di luar sisi garis luarnya, atau tepat di atas sisi itu)
        incr stamp
        set cav [list $t]
        set mark($t) $stamp
        set bnd {}
        for {set qi 0} {$qi < [llength $cav]} {incr qi} {
            set u [lindex $cav $qi]
            lassign $T($u) a b c n0 n1 n2
            foreach {v1 v2 nb} [list $b $c $n0 $c $a $n1 $a $b $n2] {
                if {[info exists mark($nb)] && $mark($nb) == $stamp} {
                    continue
                }
                lassign $T($nb) ta tb tc
                if {$ta == $G || $tb == $G || $tc == $G} {
                    # hantu: sisi nyatanya ex->ey, bagian luar garis luar ada di kirinya
                    if {$ta == $G} {
                        set ex $tb
                        set ey $tc
                    } elseif {$tb == $G} {
                        set ex $tc
                        set ey $ta
                    } else {
                        set ex $ta
                        set ey $tb
                    }
                    set ex0 [lindex $xs $ex]
                    set ey0 [lindex $ys $ex]
                    set ex1 [lindex $xs $ey]
                    set ey1 [lindex $ys $ey]
                    set o [expr {($ex1 - $ex0) * ($py - $ey0) - ($ey1 - $ey0) * ($px - $ex0)}]
                    if {$o > 1e-9 || ($o >= -1e-9
                        && ($px - $ex0) * ($ex1 - $ex0) + ($py - $ey0) * ($ey1 - $ey0) > 0
                        && ($px - $ex1) * ($ex0 - $ex1) + ($py - $ey1) * ($ey0 - $ey1) > 0)} {
                        lappend cav $nb
                        set mark($nb) $stamp
                        continue
                    }
                } else {
                    set ax [expr {[lindex $xs $ta] - $px}]
                    set ay [expr {[lindex $ys $ta] - $py}]
                    set bx [expr {[lindex $xs $tb] - $px}]
                    set by [expr {[lindex $ys $tb] - $py}]
                    set ccx [expr {[lindex $xs $tc] - $px}]
                    set ccy [expr {[lindex $ys $tc] - $py}]
                    set det [expr {($ax*$ax + $ay*$ay) * ($bx*$ccy - $ccx*$by)
                                 - ($bx*$bx + $by*$by) * ($ax*$ccy - $ccx*$ay)
                                 + ($ccx*$ccx + $ccy*$ccy) * ($ax*$by - $bx*$ay)}]
                    if {$det > 1e-12} {
                        lappend cav $nb
                        set mark($nb) $stamp
                        continue
                    }
                }
                lappend bnd $u $v1 $v2 $nb
            }
        }

        # segitiga baru: satu untuk tiap sisi batas rongga (jumlahnya = isi rongga + 2)
        set ids $cav
        lappend ids $T(next) [expr {$T(next) + 1}]
        if {[llength $bnd] / 4 != [llength $ids]} {
            error "triangulasi gagal (rongga tidak valid)"
        }
        set j 0
        set fix {}
        set fresh {}
        foreach {u v1 v2 nb} $bnd {
            set id [lindex $ids $j]
            incr j
            set startTri($v1) $id
            set endTri($v2) $id
            # tetangga di luar rongga: catat dulu posisi penunjuk ke segitiga lama, baru ubah (id dipakai ulang)
            lappend fix $nb [lsearch -exact [lrange $T($nb) 3 5] $u] $id
            lappend fresh $id $v1 $v2 $nb
        }
        foreach {nb slot id} $fix {
            lset T($nb) [expr {3 + $slot}] $id
        }
        foreach {id v1 v2 nb} $fresh {
            set T($id) [list $v1 $v2 $i $startTri($v2) $endTri($v1) $nb]
            if {$v1 != $G && $v2 != $G} {
                set last $id
            }
        }
        incr T(next) 2
    }
    return $n
}

# Nilai bidang segitiga (simpul a b c) di titik (px,py), diinterpolasi/diekstrapolasi linear dari z tiga simpulnya.
proc svPlaneZ {x1 y1 z1 x2 y2 z2 x3 y3 z3 px py} {
    set det [expr {($y2 - $y3) * ($x1 - $x3) + ($x3 - $x2) * ($y1 - $y3)}]
    if {$det == 0} {
        return [expr {($z1 + $z2 + $z3) / 3.0}]
    }
    set l1 [expr {(($y2 - $y3) * ($px - $x3) + ($x3 - $x2) * ($py - $y3)) / $det}]
    set l2 [expr {(($y3 - $y1) * ($px - $x3) + ($x1 - $x3) * ($py - $y3)) / $det}]
    return [expr {$l1 * $z1 + $l2 * $z2 + (1.0 - $l1 - $l2) * $z3}]
}

# Isi tabel dari satu string: {ok msg ...}. pts = {{x y z} ...} (koordinat asli), base = tin|plane,
# tolManual = "" (otomatis) atau toleransi tinggi dari titik terendah (dipakai apa adanya).
# Mengembalikan dict: ok, msg (bila gagal), points, band, tol, verts, plan, surf, above, below, net, status, toe.
proc svSolvePile {pts base tolManual} {
    set raw [llength $pts]
    set res [dict create ok 0 points $raw]

    # buang titik kembar (x,y sama)
    set P {}
    foreach p $pts {
        set key [format "%.4f %.4f" [lindex $p 0] [lindex $p 1]]
        if {![info exists seen($key)]} {
            set seen($key) 1
            lappend P $p
        }
    }
    set n [llength $P]
    if {$n < 3} {
        dict set res msg "kurang dari 3 titik"
        return $res
    }

    # koordinat lokal (menghindari selisih besar dua bilangan sangat besar saat menghitung luas)
    set ox [lindex $P 0 0]
    set oy [lindex $P 0 1]
    foreach p $P {
        if {[lindex $p 0] < $ox} {set ox [lindex $p 0]}
        if {[lindex $p 1] < $oy} {set oy [lindex $p 1]}
    }
    set L {}
    set zmin [lindex $P 0 2]
    set zmax $zmin
    foreach p $P {
        lassign $p x y z
        lappend L [list [expr {$x - $ox}] [expr {$y - $oy}] $z]
        if {$z < $zmin} {set zmin $z}
        if {$z > $zmax} {set zmax $z}
    }
    set range [expr {$zmax - $zmin}]

    set full [svHull $L]
    if {[llength $full] < 3 || [svPolyArea $full] <= 0} {
        dict set res msg "titik-titik segaris, tidak membentuk timbunan"
        return $res
    }

    # --- toe: titik dalam toleransi dari titik terendah; garis luarnya menjadi batas ---
    if {[string length $tolManual] == 0} {
        set tol [expr {0.05 * $range}]
        for {set iter 0} {$iter < 60} {incr iter} {
            set lim [expr {$zmin + $tol + 1e-12}]
            set band {}
            foreach p $L {
                if {[lindex $p 2] <= $lim} {
                    lappend band $p
                }
            }
            set h [svHull $band]
            if {[llength $h] >= 3 && [svPolyArea $h] > 0} {
                # semua titik berada di dalam h bila semua sudut garis luar seluruh titik berada di dalam h
                set he [svEdgeList $h]
                set allIn 1
                foreach q $full {
                    if {![svInsideEdges $he [lindex $q 0] [lindex $q 1]]} {
                        set allIn 0
                        break
                    }
                }
                if {$allIn} {
                    break
                }
            }
            set tol [expr {$tol * 1.5}]
        }
    } else {
        set tol $tolManual
        set lim [expr {$zmin + $tol + 1e-12}]
        set band {}
        foreach p $L {
            if {[lindex $p 2] <= $lim} {
                lappend band $p
            }
        }
        set h [svHull $band]
        if {[llength $h] < 3 || [svPolyArea $h] <= 0} {
            dict set res msg "toleransi toe terlalu kecil: titik toe kurang dari 3 atau segaris"
            return $res
        }
        set he [svEdgeList $h]
    }
    set plan [svPolyArea $h]

    # titik yang dipakai: yang berada di dalam garis toe
    if {[string length $tolManual] == 0} {
        set S $L
        set outside 0
    } else {
        set S {}
        foreach p $L {
            if {[svInsideEdges $he [lindex $p 0] [lindex $p 1]]} {
                lappend S $p
            }
        }
        set outside [expr {$n - [llength $S]}]
    }
    set m [llength $S]
    set sx {}
    set sy {}
    set sz {}
    foreach p $S {
        lappend sx [lindex $p 0]
        lappend sy [lindex $p 1]
        lappend sz [lindex $p 2]
    }

    # --- permukaan: Delaunay semua titik di dalam batas ---
    svDelaunay ST $sx $sy [svInsertOrder $sx $sy]

    # --- dasar ---
    set hx {}
    set hy {}
    set hz {}
    foreach p $h {
        lappend hx [lindex $p 0]
        lappend hy [lindex $p 1]
        lappend hz [lindex $p 2]
    }
    set hn [llength $h]
    set bz {}
    if {"$base" == "plane"} {
        # bidang best-fit (kuadrat terkecil) atas sudut-sudut garis toe: z = a*x + b*y + c
        set cxm 0.0
        set cym 0.0
        set czm 0.0
        foreach x $hx y $hy z $hz {
            set cxm [expr {$cxm + $x}]
            set cym [expr {$cym + $y}]
            set czm [expr {$czm + $z}]
        }
        set cxm [expr {$cxm / $hn}]
        set cym [expr {$cym / $hn}]
        set czm [expr {$czm / $hn}]
        set sxx 0.0
        set sxy 0.0
        set syy 0.0
        set sxz 0.0
        set syz 0.0
        foreach x $hx y $hy z $hz {
            set dx [expr {$x - $cxm}]
            set dy [expr {$y - $cym}]
            set dz [expr {$z - $czm}]
            set sxx [expr {$sxx + $dx * $dx}]
            set sxy [expr {$sxy + $dx * $dy}]
            set syy [expr {$syy + $dy * $dy}]
            set sxz [expr {$sxz + $dx * $dz}]
            set syz [expr {$syz + $dy * $dz}]
        }
        set det [expr {$sxx * $syy - $sxy * $sxy}]
        if {abs($det) < 1e-12} {
            set pa 0.0
            set pb 0.0
        } else {
            set pa [expr {($sxz * $syy - $syz * $sxy) / $det}]
            set pb [expr {($syz * $sxx - $sxz * $sxy) / $det}]
        }
        foreach x $sx y $sy {
            lappend bz [expr {$czm + $pa * ($x - $cxm) + $pb * ($y - $cym)}]
        }
    } else {
        # TIN dari sudut-sudut garis toe
        svDelaunay BT $hx $hy [svInsertOrder $hx $hy]
        set cur 0
        for {set t 0} {$t < $BT(next)} {incr t} {
            lassign $BT($t) a b c
            if {$a != $hn && $b != $hn && $c != $hn} {
                set cur $t
                break
            }
        }
        foreach x $sx y $sy {
            set t [svWalk BT $hx $hy $hn $cur $x $y]
            lassign $BT($t) a b c n0 n1 n2
            # titik di luar garis toe (selisih pembulatan): pakai segitiga nyata di sebelah segitiga hantu
            if {$a == $hn} {
                set t $n0
            } elseif {$b == $hn} {
                set t $n1
            } elseif {$c == $hn} {
                set t $n2
            }
            lassign $BT($t) a b c
            set cur $t
            lappend bz [svPlaneZ [lindex $hx $a] [lindex $hy $a] [lindex $hz $a] \
                                 [lindex $hx $b] [lindex $hy $b] [lindex $hz $b] \
                                 [lindex $hx $c] [lindex $hy $c] [lindex $hz $c] $x $y]
        }
    }

    # --- volume tiap segitiga permukaan: tepat, termasuk bagian yang memotong dasar ---
    set above 0.0
    set below 0.0
    set surf 0.0
    for {set t 0} {$t < $ST(next)} {incr t} {
        lassign $ST($t) a b c
        if {$a >= $m || $b >= $m || $c >= $m} {
            continue
        }
        set ax [lindex $sx $a]
        set ay [lindex $sy $a]
        set az [lindex $sz $a]
        set bx [lindex $sx $b]
        set by [lindex $sy $b]
        set bzz [lindex $sz $b]
        set cx [lindex $sx $c]
        set cy [lindex $sy $c]
        set cz [lindex $sz $c]
        set ux [expr {$bx - $ax}]
        set uy [expr {$by - $ay}]
        set uz [expr {$bzz - $az}]
        set vx [expr {$cx - $ax}]
        set vy [expr {$cy - $ay}]
        set vz [expr {$cz - $az}]
        set nx [expr {$uy * $vz - $uz * $vy}]
        set ny [expr {$uz * $vx - $ux * $vz}]
        set nz [expr {$ux * $vy - $uy * $vx}]
        set area [expr {abs($nz) / 2.0}]
        set surf [expr {$surf + 0.5 * sqrt($nx*$nx + $ny*$ny + $nz*$nz)}]
        set d0 [expr {$az - [lindex $bz $a]}]
        set d1 [expr {$bzz - [lindex $bz $b]}]
        set d2 [expr {$cz - [lindex $bz $c]}]
        if {$d0 >= 0 && $d1 >= 0 && $d2 >= 0} {
            set pv [expr {($d0 + $d1 + $d2) / 3.0}]
            set nv 0.0
        } elseif {$d0 <= 0 && $d1 <= 0 && $d2 <= 0} {
            set pv 0.0
            set nv [expr {-($d0 + $d1 + $d2) / 3.0}]
        } else {
            set npos [expr {($d0 > 0) + ($d1 > 0) + ($d2 > 0)}]
            if {$npos == 1} {
                # satu simpul di atas dasar: bagian atasnya segitiga kecil
                if {$d0 > 0} {
                    set e0 $d0; set e1 $d1; set e2 $d2
                } elseif {$d1 > 0} {
                    set e0 $d1; set e1 $d2; set e2 $d0
                } else {
                    set e0 $d2; set e1 $d0; set e2 $d1
                }
                set f [expr {($e0 / ($e0 - $e1)) * ($e0 / ($e0 - $e2))}]
                set pv [expr {$f * $e0 / 3.0}]
                set nv [expr {$pv - ($e0 + $e1 + $e2) / 3.0}]
            } else {
                # satu simpul di bawah dasar
                if {$d0 <= 0} {
                    set e0 $d0; set e1 $d1; set e2 $d2
                } elseif {$d1 <= 0} {
                    set e0 $d1; set e1 $d2; set e2 $d0
                } else {
                    set e0 $d2; set e1 $d0; set e2 $d1
                }
                set f [expr {($e0 / ($e0 - $e1)) * ($e0 / ($e0 - $e2))}]
                set nv [expr {-$f * $e0 / 3.0}]
                set pv [expr {($e0 + $e1 + $e2) / 3.0 + $nv}]
            }
        }
        set above [expr {$above + $area * $pv}]
        set below [expr {$below + $area * $nv}]
    }

    # --- status ---
    set notes {}
    if {[string length $tolManual] == 0 && $range > 0 && $tol / $range > 0.5} {
        lappend notes [format "toleransi toe melebar sampai %.0f%% dari rentang tinggi: toe praktis menjadi tepi data string ini (tanah miring, atau bukan satu timbunan)" [expr {100.0 * $tol / $range}]]
    }
    if {$outside > 0} {
        lappend notes "$outside titik di luar garis toe diabaikan"
    }
    if {$above > 1e-6 && $below > 0.1 * $above} {
        lappend notes "volume di bawah dasar lebih dari 10% volume di atasnya: dasar mungkin tidak cocok"
    }
    if {[llength $notes] == 0} {
        set status OK
    } else {
        set status [join $notes "; "]
    }

    # garis toe dalam koordinat asli
    set toe {}
    foreach p $h {
        lappend toe [list [expr {[lindex $p 0] + $ox}] [expr {[lindex $p 1] + $oy}] [lindex $p 2]]
    }

    dict set res ok 1
    dict set res band [llength $band]
    dict set res tol $tol
    dict set res verts $hn
    dict set res plan $plan
    dict set res surf $surf
    dict set res above $above
    dict set res below $below
    dict set res net [expr {$above - $below}]
    dict set res status $status
    dict set res toe $toe
    return $res
}

# ---------------------------------------------------------------------------------------------
# membaca file string
# ---------------------------------------------------------------------------------------------

# 1 bila file berisi byte 0 di awalnya (.str biner), 0 bila teks.
proc svIsBinary {file} {
    set fh [open $file rb]
    set head [read $fh 8192]
    close $fh
    return [expr {[string first "\x00" $head] >= 0}]
}

# .str teks: header, rekaman sumbu (string 0), lalu "string, Y, X, Z, deskripsi"; string 0 = pemisah segmen.
# Hasil: dict {nomor-string {{x y z} ...}}; titik Z = -999 dilewati.
proc svReadText {file} {
    set fh [open $file r]
    set data [read $fh]
    close $fh
    set result [dict create]
    set lineNo 0
    foreach line [split $data "\n"] {
        incr lineNo
        if {$lineNo == 1} {
            continue
        }
        set f [split [string trim $line] ,]
        if {[llength $f] < 4} {
            continue
        }
        if {[scan [lindex $f 0] %d no] != 1 || $no <= 0} {
            continue
        }
        if {[scan [lindex $f 1] %f y] != 1 || [scan [lindex $f 2] %f x] != 1 || [scan [lindex $f 3] %f z] != 1} {
            continue
        }
        if {abs($z + 999.0) < 1e-6} {
            continue
        }
        dict lappend result $no [list $x $y $z]
    }
    return $result
}

# Baca lewat perintah bawaan Surpac (SclSwaOpenFile): berlaku untuk .str teks maupun biner.
# (Handle objek Scl dijadikan variabel global: perintah Scl menulis handle ke variabel bernama, dan dengan cara ini
# hasilnya sama di mana pun variabel itu dibuat.)
proc svReadNative {file} {
    global svSwa svStrs svSh svSeg svPt
    set result [dict create]
    SclCreateSwa svSwa "stockpile_by_string_read_[pid]"
    if {[catch {
        $svSwa SclSwaOpenFile $file
        $svSwa SclGetStrings svStrs
        set ns [$svStrs SclCountItems]
        for {set i 0} {$i < $ns} {incr i} {
            $svStrs SclGetItem svSh $i
            set no [$svSh SclGetId]
            set nseg [$svSh SclCountItems]
            set pts {}
            for {set j 0} {$j < $nseg} {incr j} {
                $svSh SclGetItem svSeg $j
                set np [$svSeg SclCountItems]
                for {set k 0} {$k < $np} {incr k} {
                    $svSeg SclGetItem svPt $k
                    set x [$svPt SclGetValueByName x]
                    set y [$svPt SclGetValueByName y]
                    set z [$svPt SclGetValueByName z]
                    if {abs($z + 999.0) < 1e-6} {
                        continue
                    }
                    lappend pts [list $x $y $z]
                }
            }
            if {$no > 0 && [llength $pts] > 0} {
                dict set result $no $pts
            }
        }
    } err]} {
        catch {SclDestroy svSwa}
        error $err
    }
    catch {SclDestroy svSwa}
    return $result
}

# Baca file string. Mengembalikan {1 dict} atau {0 pesan}.
proc svReadStrFile {file} {
    set binary [expr {[catch {svIsBinary $file} b] ? 1 : $b}]
    set data [dict create]
    set errText ""
    if {!$binary} {
        if {[catch {svReadText $file} data]} {
            set errText $data
            set data [dict create]
        }
    }
    if {[dict size $data] == 0} {
        if {[catch {svReadNative $file} data]} {
            set errText $data
            set data [dict create]
        }
    }
    if {[dict size $data] == 0} {
        set msg "Tidak ada string berisi titik di $file."
        if {[string length $errText] > 0} {
            append msg "\n$errText"
        }
        return [list 0 $msg]
    }
    return [list 1 $data]
}

# ---------------------------------------------------------------------------------------------
# isian tabel, laporan, toe
# ---------------------------------------------------------------------------------------------

# Periksa baris tabel ({string titik nama berat-jenis} tiap baris) dan siapkan yang dibutuhkan hitungan.
# skip = teks berisi nomor string yang diabaikan. Mengembalikan {1 nomor dict-berat-jenis dict-nama}
# atau {0 pesan}.
proc svCheckRows {rows skip} {
    set skipList {}
    foreach s [regexp -all -inline {[0-9]+} $skip] {
        lappend skipList [svNum $s]
    }
    set numbers {}
    set dens [dict create]
    set names [dict create]
    set rowNo 0
    foreach row $rows {
        incr rowNo
        set raw [string trim [lindex $row 0]]
        if {[string length $raw] == 0} {
            continue
        }
        set n [svNum $raw]
        if {[lsearch -exact $skipList $n] >= 0} {
            continue
        }
        set name [string trim [lindex $row 1]]
        # koma desimal ("1,8") diterima juga
        set d [string map {, .} [string trim [lindex $row 2]]]
        if {[regexp {[,"]} $name]} {
            return [list 0 "Baris tabel $rowNo: nama tidak boleh berisi koma atau tanda kutip ganda."]
        }
        if {[string length $d] > 0} {
            # angka desimal biasa dengan minimal satu digit bukan nol, mis. 1.8 atau .9
            if {![regexp {^([0-9]+\.?[0-9]*|\.[0-9]+)$} $d] || ![regexp {[1-9]} $d]} {
                return [list 0 "Baris tabel $rowNo: berat jenis string $n harus angka di atas nol (diterima '$d')."]
            }
            dict set dens $n $d
        }
        if {[string length $name] > 0} {
            dict set names $n $name
        }
        lappend numbers $n
    }
    if {[llength $numbers] == 0} {
        return [list 0 "Tidak ada yang dihitung: semua string diabaikan."]
    }
    return [list 1 $numbers $dens $names]
}

# Satu baris CSV; teks yang berisi koma atau tanda kutip diberi tanda kutip.
proc svCsvQuote {text} {
    if {[regexp {[,"]} $text]} {
        return "\"[string map {\" \"\"} $text]\""
    }
    return $text
}

# Angka dengan jumlah desimal tetap (titik desimal); kosong tetap kosong.
proc svFixed {v digits} {
    if {[string length $v] == 0} {
        return ""
    }
    return [format "%.${digits}f" $v]
}

# Tulis laporan CSV (kolom sama dengan versi sebelumnya; angka memakai titik desimal).
proc svWriteCsv {csvFile results} {
    set fh [open $csvFile w]
    puts $fh "string,name,points,toe_band_points,toe_tolerance,toe_vertices,plan_area_m2,surface_area_m2,volume_above_m3,volume_below_m3,net_volume_m3,density_t_m3,tonnes,status"
    set tp 0
    set tplan 0.0
    set tab 0.0
    set tbe 0.0
    set tnet 0.0
    set tton 0.0
    set anyTon 0
    foreach r $results {
        set no [dict get $r string]
        set name [dict get $r name]
        if {![dict get $r ok]} {
            puts $fh "$no,[svCsvQuote $name],[dict get $r points],,,,,,,,,,,[svCsvQuote "GAGAL: [dict get $r msg]"]"
            continue
        }
        set dens [dict get $r density]
        set ton [dict get $r tonnes]
        puts $fh [join [list $no [svCsvQuote $name] [dict get $r points] [dict get $r band] \
            [format %.6f [dict get $r tol]] [dict get $r verts] \
            [format %.6f [dict get $r plan]] [format %.6f [dict get $r surf]] \
            [format %.6f [dict get $r above]] [format %.6f [dict get $r below]] [format %.6f [dict get $r net]] \
            [svFixed $dens 6] [svFixed $ton 6] \
            [svCsvQuote [dict get $r status]]] ,]
        incr tp [dict get $r points]
        set tplan [expr {$tplan + [dict get $r plan]}]
        set tab [expr {$tab + [dict get $r above]}]
        set tbe [expr {$tbe + [dict get $r below]}]
        set tnet [expr {$tnet + [dict get $r net]}]
        if {$ton ne ""} {
            set tton [expr {$tton + $ton}]
            set anyTon 1
        }
    }
    set tonText ""
    if {$anyTon} {
        set tonText [format %.6f $tton]
    }
    puts $fh "TOTAL,,$tp,,,,[format %.6f $tplan],,[format %.6f $tab],[format %.6f $tbe],[format %.6f $tnet],,$tonText,"
    close $fh
}

# Teks laporan untuk jendela pesan.
proc svReportText {results totals} {
    lassign $totals tplan tab tbe tnet tton anyTon
    set out [format "%6s  %-16s %13s %13s %13s %13s %6s %13s" String Nama "Luas m2" "Di atas m3" "Di bawah m3" "Bersih m3" t/m3 Ton]
    set notes {}
    foreach r $results {
        set no [dict get $r string]
        set name [dict get $r name]
        if {![dict get $r ok]} {
            append out "\n" [format "%6s  %-16s GAGAL: %s" $no $name [dict get $r msg]]
            lappend notes "String $no: GAGAL - [dict get $r msg]"
            continue
        }
        set dens [dict get $r density]
        set ton [dict get $r tonnes]
        append out "\n" [format "%6s  %-16s %13s %13s %13s %13s %6s %13s" $no $name \
            [svFmt [dict get $r plan] 2] [svFmt [dict get $r above] 2] [svFmt [dict get $r below] 2] \
            [svFmt [dict get $r net] 2] [svFmt $dens 2] [svFmt $ton 1]]
        if {[dict get $r status] ne "OK"} {
            lappend notes "String $no: PERIKSA - [dict get $r status]"
        }
    }
    append out "\n" [format "%6s  %-16s %13s %13s %13s %13s %6s %13s" TOTAL "" \
        [svFmt $tplan 2] [svFmt $tab 2] [svFmt $tbe 2] [svFmt $tnet 2] "" [expr {$anyTon ? [svFmt $tton 1] : ""}]]
    if {[llength $notes] > 0} {
        append out "\n\n[join $notes \n]"
    }
    return $out
}

# Tulis garis toe sebagai .str teks: satu string tertutup per stockpile, bernomor sama.
# toes = {{nomor {{x y z} ...}} ...}. Urutan kolom .str Surpac: string, Y, X, Z.
proc svWriteToeFile {file toes} {
    set fh [open $file w]
    fconfigure $fh -translation crlf
    puts $fh "toe,[clock format [clock seconds] -format {%d-%b-%y}],,SSI_STYLES:styles.ssi"
    puts $fh "0, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000"
    foreach t $toes {
        lassign $t no poly
        foreach p [concat $poly [list [lindex $poly 0]]] {
            puts $fh [format "%d, %.3f, %.3f, %.3f," $no [lindex $p 1] [lindex $p 0] [lindex $p 2]]
        }
        puts $fh "0, 0.000, 0.000, 0.000,"
    }
    puts $fh "0, 0.000, 0.000, 0.000, END"
    close $fh
}

# Tampilkan file toe sebagai layer di Surpac: buat SWA, tambahkan ke layer grafis, muat file, gambar.
# Mengembalikan 1 bila berhasil; bila gagal hanya mencetak catatan, karena hitungannya sendiri sudah selesai.
proc svShowToes {toePath} {
    global SCL_TRUE svVp svSwa svStrs
    set loc [file normalize $toePath]
    set layerName "toe_by_string"
    if {[catch {
        SclGetActiveViewport svVp
        set existed [SclSwaExists $layerName]
        SclCreateSwa svSwa $layerName
        if {$existed == $SCL_TRUE} {
            # layer dari jalannya makro sebelumnya: buang, supaya tidak bertumpuk
            SclDestroy svSwa
            SclCreateSwa svSwa $layerName
        }
        sclGraphicsLayers SclAdd $svSwa $svVp
        $svSwa SclSwaOpenFile $loc
        SclFunction "ZOOM ALL" {}
        $svSwa SclGetStrings svStrs
        $svStrs SclDraw
    } err]} {
        puts "CATATAN: toe tersimpan di $loc tetapi tidak bisa ditampilkan otomatis ($err)."
        puts "         Buka file itu dengan fungsi OPEN FILE untuk memeriksanya."
        return 0
    }
    puts "Toe ditampilkan sebagai layer $layerName (nomor string sama dengan stockpile-nya)."
    return 1
}

# Jangan lanjut bila file ini hanya dimuat untuk pengujian fungsi (di luar Surpac).
if {[info exists svTestMode]} {
    return
}

# ---------------------------------------------------------------------------------------------
# definisi form
# ---------------------------------------------------------------------------------------------

set svForm1Def {
    GuidoForm svForm1 {
        -label "Volume stockpile per string - langkah 1 dari 2"
        -default_buttons
        GuidoPanel intro_panel {
            -layout BoxLayout Y_AXIS
            GuidoLabel intro_line1 {
                -label "<html><b>Volume Auto Toe untuk beberapa stockpile dalam satu file</b></html>"
            }
            GuidoLabel intro_line2 {
                -label "<html>Pilih file string. Langkah 2 menampilkan string yang ada di dalamnya, satu string satu stockpile.</html>"
            }
            GuidoFiller intro_gap {
                -height 1
            }
        }
        GuidoFileBrowserField file_str {
            -label "File string (.str)"
            -width 40
            -file_mask "*.str"
            -absolutePath true
            -file_access exist
            -null false
            -tip "File string Surpac (teks atau biner) berisi satu stockpile per string"
        }
    }
}

# @INFO@ = baris HTML, @N@ = jumlah baris tabel, @HEIGHT@ = jumlah baris tabel yang tampak
set svForm2Template {
    GuidoForm svForm2 {
        -label "Volume stockpile per string - langkah 2 dari 2"
        -default_buttons
        GuidoPanel info_panel {
            -layout BoxLayout Y_AXIS
            GuidoLabel info_line {
                -label "@INFO@"
            }
            GuidoFiller info_gap {
                -height 1
            }
        }
        GuidoScrollPane pile_scroller {
            -label "Stockpile (satu baris per string)"
            -border etched true
            -height @HEIGHT@
            GuidoTable pile_table {
                -instances @N@ @N@ @N@
                -interactive false
                -row_header_width 10
                GuidoField str_no {
                    -label "String"
                    -width 6
                    -format integer
                    -input false
                }
                GuidoField str_pts {
                    -label "Titik"
                    -width 7
                    -format integer
                    -input false
                }
                GuidoField str_name {
                    -label "Nama (opsional)"
                    -width 18
                    -format none
                    -null true
                    -tip "Nama stockpile ini di laporan (tanpa koma atau tanda kutip)"
                }
                GuidoField str_density {
                    -label "Berat jenis t/m3"
                    -width 12
                    -format double
                    -low_bound 0.05
                    -high_bound 20
                    -null true
                    -tip "Berat jenis stockpile ini dalam t/m3, dipakai untuk ton. Kosong = hanya volume."
                }
            }
        }
        GuidoPanel options_panel {
            -label "Opsi"
            -border etched true
            -layout CentreLineLayout
            GuidoField skip_strings {
                -label "Abaikan string"
                -width 14
                -format none
                -null true
                -tip "Nomor string yang bukan stockpile, mis. 3,5 - tidak dihitung"
            }
            GuidoCheckBox base_plane {
                -label "Jenis dasar"
                -caption "Bidang best-fit (tanpa centang: TIN dari toe)"
                -selected_value "plane"
                -unselected_value "tin"
                -height 1
                -tip "TIN mengikuti ketinggian toe; bidang cocok untuk tanah yang datar dan rata"
            }
            GuidoField toe_tol {
                -label "Toleransi toe (kosong = otomatis)"
                -width 12
                -format double
                -low_bound 0
                -null true
                -tip "Titik dalam ketinggian ini dari titik terendah sebuah string dianggap toe-nya. Kosong: melebar otomatis."
            }
            GuidoCheckBox save_toe {
                -label "Garis toe"
                -caption "Simpan sebagai .str dan tampilkan di Surpac"
                -selected_value "yes"
                -unselected_value "no"
                -height 1
                -tip "Menyimpan toe hasil deteksi di samping file input dan membukanya sebagai layer untuk diperiksa"
            }
            GuidoField report_csv {
                -label "Simpan laporan CSV (opsional)"
                -width 40
                -format none
                -null true
            }
        }
    }
}

# @SUMMARY@ = baris ringkasan HTML, @N@ = jumlah baris tabel, @HEIGHT@ = jumlah baris tabel yang tampak
set svForm3Template {
    GuidoForm svForm3 {
        -label "Volume stockpile per string - hasil"
        -default_buttons
        GuidoPanel summary_panel {
            -layout BoxLayout Y_AXIS
            GuidoLabel summary_line {
                -label "@SUMMARY@"
            }
            GuidoFiller summary_gap {
                -height 1
            }
        }
        GuidoScrollPane res_scroller {
            -label "Hasil"
            -border etched true
            -height @HEIGHT@
            GuidoTable res_table {
                -instances @N@ @N@ @N@
                -interactive false
                -row_header_width 10
                GuidoField res_string {
                    -label "String"
                    -width 8
                    -format none
                    -input false
                }
                GuidoField res_name {
                    -label "Nama"
                    -width 16
                    -format none
                    -input false
                }
                GuidoField res_area {
                    -label "Luas m2"
                    -width 11
                    -format none
                    -input false
                }
                GuidoField res_net {
                    -label "Volume bersih m3"
                    -width 15
                    -format none
                    -input false
                }
                GuidoField res_density {
                    -label "t/m3"
                    -width 6
                    -format none
                    -input false
                }
                GuidoField res_tonnes {
                    -label "Ton"
                    -width 11
                    -format none
                    -input false
                }
                GuidoField res_check {
                    -label "Cek"
                    -width 8
                    -format none
                    -input false
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------------------------
# dialognya (tingkat atas skrip: form Guido mengembalikan nilainya ke tingkat ini)
# ---------------------------------------------------------------------------------------------

# ---- langkah 1: file ----
set svGo 0
SclCreateGuidoForm svH1 $svForm1Def {
    set file_str ""
}
$svH1 SclRun {
    if {"$_status" == "apply"} {
        set svGo 1
        set svFile [string trim $file_str]
    }
}
if {!$svGo} {
    puts "Dibatalkan."
    return
}
if {![file exists $svFile]} {
    puts "KESALAHAN: file string tidak ditemukan: $svFile"
    return
}

puts "Membaca $svFile ..."
lassign [svReadStrFile $svFile] svOk svData
if {!$svOk} {
    puts "KESALAHAN: $svData"
    return
}
# svData = dict {nomor-string {{x y z} ...}}
set svNos [lsort -integer [dict keys $svData]]
set svCount [llength $svNos]
set svShown {}
foreach svK $svNos {
    lappend svShown [list $svK [llength [dict get $svData $svK]]]
}
set svNote ""
if {$svCount > $svMaxPiles} {
    set svShown [lrange $svShown 0 [expr {$svMaxPiles - 1}]]
    set svNote "<br><font color=red>File berisi $svCount string; hanya $svMaxPiles yang pertama ditampilkan. Naikkan svMaxPiles di bagian atas makro untuk menampilkan lebih banyak.</font>"
    puts "CATATAN: file berisi $svCount string; hanya $svMaxPiles yang pertama ditampilkan (svMaxPiles)."
}
set svN [llength $svShown]

# ---- langkah 2: stockpile ----
set svInfo "<html><b>[svEsc [file tail $svFile]]</b> berisi $svCount string.<br>Isi berat jenis (t/m3) tiap stockpile; jika kosong, hanya volume yang dihitung (tanpa ton). Nama boleh dikosongkan.$svNote</html>"
set svForm2Def [string map [list @INFO@ $svInfo @N@ $svN @HEIGHT@ [expr {min($svN, 12) + 2}]] $svForm2Template]

SclCreateGuidoForm svH2 $svForm2Def {
    for {set svI 0} {$svI < $svN} {incr svI} {
        set str_no($svI) [lindex [lindex $svShown $svI] 0]
        set str_pts($svI) [lindex [lindex $svShown $svI] 1]
        set str_name($svI) ""
        set str_density($svI) ""
    }
    set skip_strings ""
    set toe_tol ""
    set report_csv ""
}
set svGo 0
$svH2 SclRun {
    if {"$_status" == "apply"} {
        set svGo 1
        set svRows {}
        for {set svI 0} {$svI < [array size str_no]} {incr svI} {
            lappend svRows [list $str_no($svI) $str_name($svI) $str_density($svI)]
        }
        set svSkip $skip_strings
        set svPlane $base_plane
        set svTol [string map {, .} [string trim $toe_tol]]
        set svSaveToe $save_toe
        set svReport [string trim $report_csv]
    }
}
if {!$svGo} {
    puts "Dibatalkan."
    return
}

lassign [svCheckRows $svRows $svSkip] svOk svNumbers svDens svNames
if {!$svOk} {
    puts "KESALAHAN: $svNumbers"
    return
}
if {[string length $svTol] > 0 && ![regexp {^([0-9]+\.?[0-9]*|\.[0-9]+)$} $svTol]} {
    puts "KESALAHAN: toleransi toe harus angka (diterima '$svTol')."
    return
}

# ---- hitung ----
puts "Menghitung [llength $svNumbers] stockpile dari [file tail $svFile] ..."
set svResults {}
set svToes {}
set svTotals [list 0.0 0.0 0.0 0.0 0.0 0]
foreach svNo $svNumbers {
    set svName ""
    if {[dict exists $svNames $svNo]} {
        set svName [dict get $svNames $svNo]
    }
    if {[string length $svName] == 0} {
        set svName "Stockpile $svNo"
    }
    set svDen ""
    if {[dict exists $svDens $svNo]} {
        set svDen [dict get $svDens $svNo]
    }
    if {[catch {svSolvePile [dict get $svData $svNo] $svPlane $svTol} svR]} {
        set svR [dict create ok 0 msg "kesalahan hitung: $svR" points [llength [dict get $svData $svNo]]]
    }
    dict set svR string $svNo
    dict set svR name $svName
    dict set svR density $svDen
    dict set svR tonnes ""
    if {[dict get $svR ok]} {
        if {[string length $svDen] > 0} {
            dict set svR tonnes [expr {[dict get $svR net] * $svDen}]
        }
        lassign $svTotals svTp svTa svTb svTn svTt svTany
        set svTp [expr {$svTp + [dict get $svR plan]}]
        set svTa [expr {$svTa + [dict get $svR above]}]
        set svTb [expr {$svTb + [dict get $svR below]}]
        set svTn [expr {$svTn + [dict get $svR net]}]
        if {[string length [dict get $svR tonnes]] > 0} {
            set svTt [expr {$svTt + [dict get $svR tonnes]}]
            set svTany 1
        }
        set svTotals [list $svTp $svTa $svTb $svTn $svTt $svTany]
        lappend svToes [list $svNo [dict get $svR toe]]
    }
    lappend svResults $svR
}

# ---- laporan ----
puts [svReportText $svResults $svTotals]
if {[string length $svReport] > 0} {
    if {[catch {svWriteCsv $svReport $svResults} svErr]} {
        puts "CATATAN: laporan CSV tidak bisa ditulis ($svErr)."
    } else {
        puts "Laporan CSV: $svReport"
    }
}

# ---- tabel hasil ----
set svRN [expr {[llength $svResults] + 1}]
set svWarn 0
foreach svR $svResults {
    if {![dict get $svR ok] || [dict get $svR status] ne "OK"} {
        incr svWarn
    }
}
lassign $svTotals svTp svTa svTb svTn svTt svTany
set svSummary "<html><b>Total volume bersih:</b> [svFmt $svTn 2] m3"
if {$svTany} {
    append svSummary " &nbsp;&nbsp; <b>Total ton:</b> [svFmt $svTt 1]"
}
if {$svWarn > 0} {
    append svSummary "<br><font color=red>$svWarn stockpile perlu diperiksa - lihat jendela pesan untuk rinciannya.</font>"
}
append svSummary "</html>"
set svForm3Def [string map [list @SUMMARY@ $svSummary @N@ $svRN @HEIGHT@ [expr {min($svRN, 12) + 2}]] $svForm3Template]

SclCreateGuidoForm svH3 $svForm3Def {
    set svI 0
    foreach svR $svResults {
        if {![dict get $svR ok]} {
            set svCheck "GAGAL"
            set svArea ""
            set svNet ""
        } else {
            if {[dict get $svR status] eq "OK"} {
                set svCheck "OK"
            } else {
                set svCheck "Periksa"
            }
            set svArea [svFmt [dict get $svR plan] 2]
            set svNet [svFmt [dict get $svR net] 2]
        }
        set res_string($svI) [dict get $svR string]
        set res_name($svI) [dict get $svR name]
        set res_area($svI) $svArea
        set res_net($svI) $svNet
        set res_density($svI) [svFmt [dict get $svR density] 2]
        set res_tonnes($svI) [svFmt [dict get $svR tonnes] 1]
        set res_check($svI) $svCheck
        incr svI
    }
    set res_string($svI) TOTAL
    set res_name($svI) ""
    set res_area($svI) [svFmt $svTp 2]
    set res_net($svI) [svFmt $svTn 2]
    set res_density($svI) ""
    set res_tonnes($svI) [expr {$svTany ? [svFmt $svTt 1] : ""}]
    set res_check($svI) ""
}
$svH3 SclRun {
}

# ---- simpan dan tampilkan toe di Surpac ----
if {"$svSaveToe" == "yes" && [llength $svToes] > 0} {
    set svToeFile "[file rootname $svFile]_toe.str"
    if {[catch {svWriteToeFile $svToeFile $svToes} svErr]} {
        puts "CATATAN: file toe tidak bisa disimpan ($svErr)."
    } else {
        puts "Toe disimpan: $svToeFile"
        svShowToes $svToeFile
    }
}
