      def count_transpositions(string_a, string_b, matches_a, matches_b)
        k = 0
        transpositions = 0
        string_a.each_char.with_index do |char, i|
          next unless matches_a[i]

          k += 1 until matches_b[k]
          transpositions += 1 if char != string_b[k]
          k += 1
        end
        transpositions / 2
      end
