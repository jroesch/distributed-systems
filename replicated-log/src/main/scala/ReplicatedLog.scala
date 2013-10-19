package replicatedlog

import shapeless._
import UnaryTCConstraint._
import scalaz._
import scalaz.effect._
import scalaz.syntax.monad._
import scalaz.Free._
import scalaz.Trampoline._
import scalaz.syntax.applicative._
import scala.tools.jline.console.ConsoleReader
import atto._
import Atto._
import IO.{ io, putStrLn }

object ReplicatedLog extends SafeApp {
  override def run(args: ImmutableArray[String]) = foreverIO(loop)

  def loop: IO[Unit] = for {
    console <- Console.withPrompt("> ")
    line <- console.readLine
    _ <- putStrLn(line)
  } yield ()


  def foreverIO[A, B >: Nothing](m: IO[A]): IO[B] = m >>= (_ => foreverIO(m))

  def emptyParams
  def params[R, H <: HList : *->*[Parser]#λ](ps: Parser[R] :: H)(implicit ua: UnapplyHParser.Aux[Parser[R] :: H, Option[(Parser[R], H)]]):
  Parser[HList] = ps match {
    case _ : HNil => HNil
    case x <:: xs => params(xs)
  }

  def command(cmd: Parser[String]) = (
      string("Increment") ~ parens(digit)
    | string("getValue")  ~ parens(digit)
  )
  
  def quotes[A](p: Parser[A]) = ???

  def parens[A](p: Parser[A]): Parser[A] = 
    (char('(') ~> p) <~ char(')')

  trait UnapplyHParser[H <: HList] extends DepFn1[H]

  trait LowPriorityHParser {
    type Aux[L <: HList, Out0] = UnapplyHParser[L] { type Out = Out0 }
    implicit def unapplyHCons[H, T <: HList : *->*[Parser]#λ]: Aux[Parser[H] :: T, Option[(Parser[H], T)]] =
      new UnapplyHParser[Parser[H] :: T] {
        type Out = Option[(Parser[H], T)]
        def apply(l : Parser[H] :: T): Out = Option((l.head, l.tail))
      }
  }

  object UnapplyHParser extends LowPriorityHParser {
    implicit def unapplySingleton[H]: Aux[Parser[H] :: HNil, Option[(Parser[H], HNil)]] =
      new UnapplyHParser[Parser[H] :: HNil] {
        type Out = Option[(Parser[H], HNil)]
        def apply(l : Parser[H] :: HNil): Out = Option((l.head, HNil))
      }
  }

  object PNil {
    def unapply[Out](l: HList)(implicit ua: UnapplyHParser.Aux[HNil, Out]): Out = ua(HNil)
  }

  object <:: {
    def unapply[L <: HList : *->*[Parser]#λ, Out](l: L)(implicit ua: UnapplyHParser.Aux[L, Out]): Out = ua(l)
  }
}

object Console {
  def withPrompt(prompt: String): IO[Console] = IO(Console(prompt))
}

case class Console(prompt: String) {
  private val console = new ConsoleReader()
  console.setPrompt(prompt)

  def readLine: IO[String] = 
    io(rw => done(rw -> { console.readLine() }))
}


    
