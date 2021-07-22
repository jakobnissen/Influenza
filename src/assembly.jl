# Protein errors
"Struct representing an indel compared to the reference"
struct Indel
    # range: Position in ref (del) or asm (ins) of bases affected
    range::UnitRange{UInt32}
    # position: seq aligns between pos and pos+1 in the other seq
    position::UInt32
    is_deletion::Bool

    function Indel(range, pos, isdel)
        rng = convert(UnitRange{UInt32}, range)
        isempty(rng) && throw(ArgumentError("Cannot have zero-length indel"))
        new(rng, convert(UInt32, pos), convert(Bool, isdel))
    end
end

Base.length(x::Indel) = length(x.range)

function indel_message(x::Indel)
    rangestring = string(first(x.range)) * '-' * string(last(x.range))
    posstring = string(x.position) * '/' * string(x.position + 1)
    if x.is_deletion
        "Deletion of ref pos " * rangestring * " b/w pos " * posstring
    else
        "Insertion of bases " * rangestring * " b/w ref pos " * posstring
    end
end

abstract type InfluenzaError end
abstract type SegmentError <: InfluenzaError end
abstract type ProteinError <: InfluenzaError end

"Protein or DNA sequence has too low identity compared to the reference"
struct ErrorLowIdentity <: InfluenzaError
    identity::Float32
end

function Base.print(io::IO, x::ErrorLowIdentity)
    percent = round(x.identity * 100, digits=1)
    print(io, "Identity to reference low at ", percent, " %")
end

"The segment is too short"
struct ErrorTooShort <: SegmentError
    len::UInt32
end

function Base.print(io::IO, x::ErrorTooShort)
    print(io, "Sequence too short at ", x,len, (isone(x.len) ? " base" : " bases"))
end

"Too many bases are insignificantly called in the sequence"
struct ErrorInsignificant <: SegmentError
    n_insignificant::UInt32
end

function Base.print(io::IO, x::ErrorInsignificant)
    print(io,
        "Sequence has ", x.n_insignificant, " insignificant ",
        (isone(x.n_insignificant) ? "base" : "bases")
    )
end

"Too many bases or amino acids are ambiguous"
struct ErrorAmbiguous <: SegmentError
    n_ambiguous::UInt32
end

function Base.print(io::IO, x::ErrorAmbiguous)
    print(io,
        "Sequence has ", x.n_ambiguous, " ambiguous ",
        (isone(x.n_ambiguous) ? "base" : "bases")
    )
end

"Some particular bases have too low depth"
struct ErrorLowDepthBases <: SegmentError
    n::UInt32
end

function Base.print(io::IO, x::ErrorLowDepthBases)
    print(io, "Sequence has ", x.n, " low-depth ", (isone(x.n) ? "base" : "bases"))
end

"Fraction of reference covered by reads/query is too low"
struct ErrorLowCoverage <: SegmentError
    coverage::Float32
end

function Base.print(io::IO, x::ErrorLowCoverage)
    n = @sprintf("%.3f", x.coverage)
    print(io, "Coverage is low at ", n)
end

"N'th round of assembly is too different from N-1'th round"
struct ErrorAssemblyNotConverged <: SegmentError
    identity::Float32
end

function Base.print(io::IO, x::ErrorAssemblyNotConverged)
    percent = round(x.identity * 100, digits=1)
    print(io, "Assembly not converged, at ", percent, " % identity")
end

"Sequence is flanked by invalid sequences - probably linkers or primers"
struct ErrorLinkerContamination <: SegmentError
    fiveprime:: Union{Nothing, UInt32}
    threeprime::Union{Nothing, UInt32}

    function ErrorLinkerContamination(fiveprime, threeprime)
        fp = convert(Union{Nothing, UInt32}, fiveprime)
        tp = convert(Union{Nothing, UInt32}, threeprime)
        if fp === tp === nothing
            throw(ArgumentError("Both fields cannot be `nothing`"))
        end
        new(fp, tp)
    end
end

function Base.print(io::IO, x::ErrorLinkerContamination)
    s = "Linker/primer contamination at ends, check "
    both = (x.fiveprime !== nothing) & (x.threeprime !== nothing)
    if x.fiveprime !== nothing
        s *= "first " * string(x.fiveprime) * (isone(x.fiveprime) ? " base" : " bases")
    end
    if x.threeprime !== nothing
        both && (s *= " and ")
        s *= "last " * string(x.threeprime) * (isone(x.threeprime) ? " base" : " bases")
    end
    print(io, s)
end

"The segment is missing a non-auxiliary protein"
struct ErrorMissingProtein <: SegmentError
    protein::Protein
end

function Base.print(io::IO, x::ErrorMissingProtein)
    print(io, "Missing non-auxiliary protein: \"", x.protein, '\"')
end

"Frameshift mutation"
struct ErrorFrameShift <: ProteinError
    indel::Indel
end

function Base.print(io::IO, x::ErrorFrameShift)
    print(io, "Frameshift: ", indel_message(x.indel))
end

"An indel is too big to be biologically plausible, or needs special attention"
struct ErrorIndelTooBig <: ProteinError
    indel::Indel
end

function Base.print(io::IO, x::ErrorIndelTooBig)
    print(io, "Indel too big: ", indel_message(x.indel))
end

"5' end of protein is deleted. This rarely happens naturally, and merits special attention"
struct ErrorFivePrimeDeletion <: ProteinError
    indel::Indel
end

function Base.print(io::IO, x::ErrorFivePrimeDeletion)
    print(io,
        "Deletion of ", length(x.indel),
        (isone(length(x.indel)) ? " base" : " bases"),
        " at 5' end"
    )
end

"Frameshift or substitution added a stop codon too early compared to reference"
struct ErrorEarlyStop <: ProteinError
    # We can't necessarily have expected pos, because the sequence may simply
    # stop before that part that aligns to the expected stop, so we can't
    # look at the alignment and see where the segment ought to stop.
    observed_pos::UInt32
    expected_naa::UInt32
    observed_naa::UInt32
end

function Base.print(io::IO, x::ErrorEarlyStop)
    print(
        io,
        "Protein stops early at segment pos ", x.observed_pos,
        " after ", x.observed_naa, " aa, reference is ",
        x.expected_naa, " aa"
    )
end

"Stop codon is mutated, protein stops later than expected"
struct ErrorLateStop <: ProteinError
    expected_pos::UInt32
    observed_pos::UInt32
    expected_naa::UInt32
    observed_naa::UInt32
end

function Base.print(io::IO, x::ErrorLateStop)
    print(
        io,
        "Protein stops late at segment pos ", x.observed_pos,
        " after ", x.observed_naa, " aa, reference stops at ",
        x.expected_stop, " after ", x.expected_naa, " aa"
    )
end

"ORF runs over edge of DNA sequence"
struct ErrorNoStop <: ProteinError end

function Base.print(io::IO, x::ErrorNoStop)
    print(io, "No stop codon")
end

"Length of coding sequence is not divisible by 3."
struct ErrorCDSNotDivisible <: ProteinError
    len::UInt32

    function ErrorCDSNotDivisible(x)
        len = convert(UInt32, x)
        if iszero(len % 3)
            throw(ArgumentError("Length must not be divisible by 3"))
        end
        new(len)
    end
end

function Base.print(io::IO, x::ErrorCDSNotDivisible)
    print(io, "CDS has length ", x.len, ", not divisible by 3")
end

"""
ReferenceProtein

Struct that holds data of one ORF in a segment.
"""
struct ReferenceProtein
    var::Protein
    orfs::Vector{UnitRange{UInt32}}
end

# This constructor validates orfs - may not be necessary
function ReferenceProtein(
    protein::Protein,
    orfs::Vector{<:UnitRange{<:Unsigned}},
    seq::NucleotideSeq
)
    issorted(orfs) || sort!(orfs)
    seqlen = length(seq)
    for orf in orfs
        if isempty(orf) || iszero(first(orf)) || last(orf) > seqlen
            throw(BoundsError(seq, orf))
        end
    end
    ReferenceProtein(protein, orfs)
end

"""
A Reference that an assembly can be compared against.

A reference holds a name, a segment, a DNA sequence, and a vector of `ReferenceProtein`, which gives the proteins encoded by the segment and their open reading frames.
"""
struct Reference
    name::String
    segment::Segment
    seq::LongDNASeq
    proteins::Vector{ReferenceProtein}
end

"""
A DNA sequence representing an influenza segment.

Assemblies consists of a name, a DNA sequence, and optionally a `Segment` and a
bitvector, signifying the bases that are insignificantly called.

# Examples
```
julia> asm = Assembly("myseq", dna"ACC")
Assembly("myseq", ACC, none(Segment), none(BitVector))

julia> asm = Assembly("myseq2", dna"TC", some(Segments.PB1), some(trues(3)))
Assembly("myseq2", TC, some(InfluenzaCore.Segments.PB1), some(Bool[1, 1, 1]))
```
"""
struct Assembly
    name::String
    seq::LongDNASeq
    # none means unknown
    segment::Option{Segment}
    # none means no bases are insignificant, or unknown
    insignificant::Option{BitVector}
end

function Assembly(name::AbstractString, seq::BioSequence{<:NucleicAcidAlphabet})
    return Assembly(
        convert(String, name),
        convert(LongDNASeq, seq),
        none(Segment),
        none(BitVector)
    )
end

function Assembly(record::FASTA.Record, segment::Union{Segment, Nothing}, check_significance::Bool=true)
    itr = (i in UInt8('a'):UInt8('z') for i in @view record.data[record.sequence])
    insignificant = check_significance && any(itr) ? some(BitVector(itr)) : none(BitVector)
    name = let
        header = FASTA.header(record)
        header === nothing ? "" : header
    end
    seq = FASTA.sequence(LongDNASeq, record)
    sgmt = segment === nothing ? none(Segment) : some(segment)
    return Assembly(name, seq, sgmt, insignificant)
end

"""
A struct to store the information about a protein in an assembly, which has
been compared to its reference. See the fields of the struct for its information.
"""
struct AssemblyProtein
    variant::Protein
    orfs::Option{Vector{UnitRange{UInt32}}}
    identity::Option{Float64}
    errors::Vector{ProteinError}
end

function AssemblyProtein(
    protein::ReferenceProtein,
    aln::PairwiseAlignment{LongDNASeq, LongDNASeq},
    ref::Reference
)
    coding_mask = falses(length(ref.seq))
    for orf in protein.orfs
        coding_mask[orf] .= true
    end

    orfseq, orfs, errors, indels = compare_proteins_in_alignment(protein, coding_mask, aln)
    aaseq = BioSequences.translate(orfseq)
    ref_aas = (i for (i,n) in zip(ref.seq, coding_mask) if n)
    # Last 3 nts are the stop codon
    refaa = BioSequences.translate(LongDNASeq(collect(ref_aas)[1:end-3]))
    aaaln = pairalign(GlobalAlignment(), aaseq, refaa, DEFAULT_AA_ALN_MODEL).aln
    @assert aaaln !== nothing

    # The orfseq can be empty if the alignment has sufficiently low identity.
    # in this case, we will store orfs and identity as none.
    (identity, orfs) = if isempty(orfseq)
        none(Float64), none(Vector{UnitRange{UInt32}})
    else
        some(alignment_identity(aaaln)::Float64), some(orfs)
    end
    return AssemblyProtein(protein.var, orfs, identity, errors)
end

"""
    is_stop(x::DNACodon)

Return whether the DNA Codon (a 3-mer) is TAA, TAG or TGA.
"""
is_stop(x::DNACodon) = (x === mer"TAA") | (x === mer"TAG") | (x === mer"TGA")

"Adds one nt at the end of the codon, moving it. If nt is ambiguous, return `nothing`"
function push_codon(x::DNACodon, nt::DNA)
    val = @inbounds BioSequences.twobitnucs[reinterpret(UInt8, nt) + 1]
    enc = (reinterpret(UInt64, x) << 2 | val) & UInt64(0x3f)
    ifelse(val === 0xff, nothing, reinterpret(DNACodon, enc))
end

"""Compares a protein and an alignment between a segment containing the protein
and the referece segment that contains that protein.
"""
function compare_proteins_in_alignment(
    protein::ReferenceProtein,
    coding_mask::BitVector,
    aln::PairwiseAlignment{LongDNASeq, LongDNASeq}
)::Tuple{LongDNASeq, Vector{UnitRange{UInt32}}, Vector{ProteinError}, Vector{Indel}}
    nucleotides = sizehint!(DNA[], 1200)
    last_coding_ref_pos = last(last(protein.orfs))
    codon = mer"AAA" # arbitrary starting codon
    seg_pos = ref_pos = n_deletions = n_insertions = 0
    fiveprime_truncated = 0
    maybe_expected_stop = none(Int)
    errors = ProteinError[]
    indels = Indel[]
    orfs = UnitRange{UInt32}[]
    seg_orfstart = nothing


    for (seg_nt, ref_nt) in aln
        seg_pos += (seg_nt !== DNA_Gap)
        ref_pos += (ref_nt !== DNA_Gap)
        is_coding = !iszero(ref_pos) && coding_mask[ref_pos]

        # Check for 5' truncation
        if iszero(seg_pos)
            fiveprime_truncated += is_coding
        else
            if !iszero(fiveprime_truncated)
                indel = Indel(
                    UInt32(ref_pos - n_deletions):UInt32(ref_pos - 1),
                    0,
                    true
                )
                push!(errors, ErrorFivePrimeDeletion(indel))
            end
            fiveprime_truncated = 0
        end

        # Add ORF if is coding and update seg_orfstart if applicable
        if is_coding
            if (seg_orfstart === nothing) & (seg_nt !== DNA_Gap)
                seg_orfstart = seg_pos
            end
        else
            if seg_orfstart !== nothing
                push!(orfs, UInt32(seg_orfstart):UInt32(seg_pos - 1))
                seg_orfstart = nothing
            end
        end

        if ref_pos == last_coding_ref_pos
            maybe_expected_stop = some(Int(seg_pos))
        end

        # All the rest of the operations only make sense if
        # the sequence is coding
        is_coding || continue

        # Check for deletions and update the codon
        if seg_nt == DNA_Gap
            n_deletions += 1
        else
            codon = let
                p = push_codon(codon, seg_nt)
                p === nothing ? mer"AAA" : p
            end
            push!(nucleotides, seg_nt)
            if !iszero(n_deletions)
                indel = Indel(
                    UInt32(ref_pos - n_deletions):UInt32(ref_pos - 1),
                    seg_pos - 1,
                    true
                )
                push!(indels, indel)
                if !iszero(length(indel) % 3)
                    push!(errors, ErrorFrameShift(indel))
                end
                if length(indel) > 21
                    push!(errors, ErrorIndelTooBig(indel))
                end
                n_deletions = 0
            end
        end

        # Check for insertions
        if ref_nt == DNA_Gap
            n_insertions += 1
        elseif !iszero(n_insertions)
            indel = Indel(
                UInt32(seg_pos - n_insertions):UInt32(seg_pos - 1),
                ref_pos - 1,
                false
            )
            push!(indels, indel)
            if !iszero(length(indel) % 3)
                push!(errors, ErrorFrameShift(indel))
            end
            if length(indel) > 36
                push!(errors, ErrorIndelTooBig(indel))
            end
            n_insertions = 0
        end

        # Only stop if we find a stop codon NOT in an intron
        if is_stop(codon) && iszero(length(nucleotides) % 3)
            n_aa = div(length(nucleotides), 3)
            expected_n_aa = div(sum(coding_mask), 3)

            # If we haven't yet reached the point where the stop ought to be
            if is_error(maybe_expected_stop)
                push!(errors, ErrorEarlyStop(seg_pos, expected_n_aa, n_aa))
            else
                expected_stop = unwrap(maybe_expected_stop)
                if expected_stop != seg_pos
                    @assert seg_pos > expected_stop
                    push!(errors, ErrorLateStop(expected_stop, seg_pos, expected_n_aa, n_aa))
                end
            end
            break
        end
    end

    # Add final orf after loop
    if seg_orfstart !== nothing
        push!(orfs, UInt16(seg_orfstart):UInt16(seg_pos))
    end

    dnaseq = LongDNASeq(nucleotides)
    # Is seq length divisible by three?
    remnant = length(dnaseq) % 3
    if !iszero(remnant)
        push!(errors, ErrorCDSNotDivisible(length(dnaseq)))
    end

    # Does it end with a stop? If so, remove it, else report error
    dnaseq = iszero(remnant) ? dnaseq : dnaseq[1:end-remnant]
    if isempty(dnaseq) || !is_stop(DNACodon(dnaseq[end-2:end]))
        push!(errors, ErrorNoStop())
    else
        dnaseq = dnaseq[1:end-3]
    end

    return dnaseq, orfs, errors, indels
end


"""
    AlignedAssembly

Struct to store information about a DNA sequence aligned to its reference.
Creating this object automatically aligns the assembly to the reference and validates
it, adding any errors to its `errors` field.

See the fields of the struct for the information contained.
"""
struct AlignedAssembly
    assembly::Assembly
    reference::Reference
    aln::PairwiseAlignment{LongDNASeq, LongDNASeq}
    identity::Float64
    proteins::Vector{AssemblyProtein}
    errors::Vector{Union{ErrorLowIdentity, SegmentError}}
end

function AlignedAssembly(asm::Assembly, ref::Reference)
    if unwrap_or(asm.segment, ref.segment) !== ref.segment
        error("Cannot make AlignedAssembly of different segments")
    end

    # For optimization: The large majority of time is spent on this alignment
    aln = pairalign(OverlapAlignment(), asm.seq, ref.seq, DEFAULT_DNA_ALN_MODEL).aln
    @assert aln !== nothing

    identity = alignment_identity(aln)::Float64

    proteins = map(ref.proteins) do protein
        AssemblyProtein(protein, aln, ref)
    end

    errors = Union{ErrorLowIdentity, SegmentError}[]

    # Insignificant bases
    n_insignificant = unwrap_or(and_then(count, Int, asm.insignificant), 0)
    iszero(n_insignificant) || push!(errors, ErrorInsignificant(n_insignificant))

    # Ambiguous bases
    n_amb = count(isambiguous, asm.seq)
    iszero(n_amb) || push!(errors, ErrorAmbiguous(n_amb))

    return AlignedAssembly(asm, ref, aln, identity, proteins, errors)
end

"""
    translate_proteins(::AlignedAssembly)

Get a vector of `Option{LongAminoAcidSeq}`, one from each protein of the aligned
assembly. If the length of the ORF is not divisible by 3, truncates bases from the 3' end.
Does not do any validation of the AA sequences.
"""
function translate_proteins(alnasm::AlignedAssembly)
    dnaseq = LongDNASeq()
    result = Option{LongAminoAcidSeq}[]
    for protein in alnasm.proteins
        if is_error(protein.orfs)
            push!(result, none(LongAminoAcidSeq))
        else
            empty!(dnaseq)
            for orf in unwrap(protein.orfs)
                append!(dnaseq, alnasm.assembly.seq[orf])
            end
            resize!(dnaseq, length(dnaseq) - length(dnaseq) % 3)
            push!(result, some(translate(dnaseq)))
        end
    end
    return result
end
